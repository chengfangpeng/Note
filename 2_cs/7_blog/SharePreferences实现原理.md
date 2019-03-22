# SP提纲

1. SP为什么进程不安全，MODE_MULTI_PROCESS是啥。
2. SP为什么加载速度慢，为什么会出现主线程等待低优先级线程锁问题，怎么预加载SP文件
3. SP为什么是全量写入
4. 什么是异地落盘的apply机制，它为什么会造成ANR
5. 怎么替换系统的SP
6. SP的替代者MMKV介绍
7. commit和apply的区别
8.　QueuedWork原理介绍
9. CountDownLatch的使用


https://blog.csdn.net/yueqian_scut/article/details/51477760
https://cloud.tencent.com/developer/article/1179555
http://gityuan.com/2017/06/18/SharedPreferences/


# 1.前言

SharedPreferences可能是我们用的最多的Android键值对存储工具了。但是它对我们来说熟悉而又陌生，熟悉是因为它使用足够简单，陌生是因为它有所谓的“七宗罪”在性能和多进程方面有一定的问题。下面我会结合源码把我们在使用中遇到的各种问题一一的解开

# 2. SharedPreferences实例的获取

SharedPreferences的创建可以有多种方式：

## 2.1 ContextWrapper中获取

```
public SharedPreferences getSharedPreferences(String name, int mode) {
       return mBase.getSharedPreferences(name, mode);
   }

```

因为我们的Activity,Service,Application都会继承ContextWrapper，所以它们也可以同样的获取SharedPreferences


## 2.2 PreferenceManager中获取

```
public static SharedPreferences getDefaultSharedPreferences(Context context) {
      return context.getSharedPreferences(getDefaultSharedPreferencesName(context),
              getDefaultSharedPreferencesMode());
  }

```

## 2.3. ContextImpl中获取并创建SharedPreferences

虽然上面获取SharedPreferences的方式很多，但是他们最终都会调用到ContextImpl.getSharedPreferences的方法，并且 SharedPreferences真正的创建也是在这里，g关于ContextImpl和Activity、Service等的关系，我会另外写篇文章介绍，其实使用的是装饰器模式.

#### 2.3.1 getSharedPreferences(String name, int mode)

```
public SharedPreferences getSharedPreferences(String name, int mode) {
       // At least one application in the world actually passes in a null
       // name.  This happened to work because when we generated the file name
       // we would stringify it to "null.xml".  Nice.
       if (mPackageInfo.getApplicationInfo().targetSdkVersion <
               Build.VERSION_CODES.KITKAT) {
           if (name == null) {
               name = "null";
           }
       }

       File file;
       synchronized (ContextImpl.class) {
           if (mSharedPrefsPaths == null) {
               mSharedPrefsPaths = new ArrayMap<>();
           }
           //从mSharedPrefsPaths查询文件
           file = mSharedPrefsPaths.get(name);
           if (file == null) {
                //如果文件不存在，根据name创建 [见2.3.2]
               file = getSharedPreferencesPath(name);
               mSharedPrefsPaths.put(name, file);
           }
       }
       //[见2.3.3]
       return getSharedPreferences(file, mode);
   }

```

#### 2.3.2 getSharedPreferencesPath(name)

```
@Override
   public File getSharedPreferencesPath(String name) {
       return makeFilename(getPreferencesDir(), name + ".xml");
   }

   //创建目录/data/data/package name/shared_prefs/
   private File getPreferencesDir() {
       synchronized (mSync) {
           if (mPreferencesDir == null) {
               mPreferencesDir = new File(getDataDir(), "shared_prefs");
           }
           return ensurePrivateDirExists(mPreferencesDir);
       }
   }

```

#### 2.3.3 getSharedPreferences(file, mode)

```
@Override
   public SharedPreferences getSharedPreferences(File file, int mode) {
      //[见2.3.4]
       checkMode(mode);
       if (getApplicationInfo().targetSdkVersion >= android.os.Build.VERSION_CODES.O) {
           if (isCredentialProtectedStorage()
                   && !getSystemService(StorageManager.class).isUserKeyUnlocked(
                           UserHandle.myUserId())
                   && !isBuggy()) {
               throw new IllegalStateException("SharedPreferences in credential encrypted "
                       + "storage are not available until after user is unlocked");
           }
       }
       SharedPreferencesImpl sp;
       synchronized (ContextImpl.class) {
          　//获取SharedPreferencesImpl的缓存集合[见2.3.5]
           final ArrayMap<File, SharedPreferencesImpl> cache = getSharedPreferencesCacheLocked();
           sp = cache.get(file);
           if (sp == null) {
                //如果缓存中没有我们就会创建SharedPreferencesImpl实例[见2.3.6]
               sp = new SharedPreferencesImpl(file, mode);
               cache.put(file, sp);
               return sp;
           }
       }

        //指定多进程模式, 则当文件被其他进程改变时,则会重新加载
       if ((mode & Context.MODE_MULTI_PROCESS) != 0 ||
           getApplicationInfo().targetSdkVersion < android.os.Build.VERSION_CODES.HONEYCOMB) {
           // If somebody else (some other process) changed the prefs
           // file behind our back, we reload it.  This has been the
           // historical (if undocumented) behavior.
           sp.startReloadIfChangedUnexpectedly();[见2.3.7]
       }
       return sp;
   }


```

#### 2.3.4 checkMode(mode)

```
private void checkMode(int mode) {
       if (getApplicationInfo().targetSdkVersion >= Build.VERSION_CODES.N) {
           if ((mode & MODE_WORLD_READABLE) != 0) {
               throw new SecurityException("MODE_WORLD_READABLE no longer supported");
           }
           if ((mode & MODE_WORLD_WRITEABLE) != 0) {
               throw new SecurityException("MODE_WORLD_WRITEABLE no longer supported");
           }
       }
   }

```

在Android24之后的版本 SharedPreferences的mode不能再使用MODE_WORLD_READABLE和MODE_WORLD_WRITEABLE。另外MODE_MULTI_PROCESS这个mode也是google不推荐使用的，因为在线上大概有万分之一的概率造成 SharedPreferences的数据全部丢失，这块的逻辑我们一会再讲。

#### 2.3.5 getSharedPreferencesCacheLocked()

```
private ArrayMap<File, SharedPreferencesImpl> getSharedPreferencesCacheLocked() {
        if (sSharedPrefsCache == null) {
            sSharedPrefsCache = new ArrayMap<>();
        }

        final String packageName = getPackageName();
        ArrayMap<File, SharedPreferencesImpl> packagePrefs = sSharedPrefsCache.get(packageName);
        if (packagePrefs == null) {
            packagePrefs = new ArrayMap<>();
            sSharedPrefsCache.put(packageName, packagePrefs);
        }

        return packagePrefs;
    }

```
通过上面的代码，我们发现ContextImpl中维护了一个存储SharedPreferencesImpl map的map缓存 sSharedPrefsCache，并且他是静态的，也就是说整个应用独此一份，而它的键是应用的包名。

#### 2.3.6 SharedPreferencesImpl的创建

前面讲了那么一大堆大多是关于SharedPreferences的各种缓存流程的，以及各种前期的准备，走到这里才真正把SharedPreferences创建出来，由于SharedPreferences是个接口，所以它的全部实现都是由
SharedPreferencesImpl来完成的。

```
SharedPreferencesImpl(File file, int mode) {
        mFile = file;
        mBackupFile = makeBackupFile(file);
        mMode = mode;
        mLoaded = false;
        mMap = null;
        startLoadFromDisk();
    }

```

#### 2.3.7
