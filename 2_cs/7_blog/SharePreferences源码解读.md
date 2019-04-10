

> 细推物理须行乐,何用浮名绊此身

# 前言
SharedPreferences（简称SP）是Android轻量级的键值对存储方式。对于开发者来说它的使用非常的方便，但是也是一种被大家诟病很多的一种存储方式。有所谓的七宗罪：
1. SP进程不安全，即使使用MODE_MULTI_PROCESS
2. 全量写入
3. 加载缓慢
4. 卡顿，apply异步落盘导致的anr

带着这些结论我们一步步的从代码中找出它的依据，当然了，本文的内容不止如此，还包裹整个SharedPreferences的运行机理等，当然这一切都是我个人的理解，中间不免有错误的地方，也欢迎大家指证。


# 2. SharedPreferences实例的获取

SharedPreferences的创建可以有多种方式：

## 2.1 ContextWrapper中获取

```
# ContextWrapper.java
public SharedPreferences getSharedPreferences(String name, int mode) {
       return mBase.getSharedPreferences(name, mode);
   }

```

因为我们的Activity,Service,Application都会继承ContextWrapper，所以它们也可以获取到SharedPreferences


## 2.2 PreferenceManager中获取

```
# PreferenceManager.java

public static SharedPreferences getDefaultSharedPreferences(Context context) {
      return context.getSharedPreferences(getDefaultSharedPreferencesName(context),
              getDefaultSharedPreferencesMode());
  }

```
通过PreferenceManager中静态方法获取，当然根据需求不通，PreferenceManager中还提供了别的方法，大家可以去查阅。

## 2.3. ContextImpl中获取并创建SharedPreferences

虽然上面获取SharedPreferences的方式很多，但是他们最终都会调用到ContextImpl.getSharedPreferences的方法，并且 SharedPreferences真正的创建也是在这里，关于ContextImpl和Activity、Service等的关系，我会另外写篇文章介绍，其实使用的是装饰器模式.

#### 2.3.1 getSharedPreferences(String name, int mode)

```

# ContextImpl.java

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
           //从mSharedPrefsPaths缓存中查询文件
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

# ContextImpl.java
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

# ContextImpl.java
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

上面的代码有个MODE_MULTI_PROCESS模式，也就是我们如果要在多进程时使用SharedPreferences时需要指定这个mode，但是这种方式google是不推荐使用的，因为在线上大概有万分之一的概率造成 SharedPreferences的数据全部丢失，因为它没有使用任何进程锁的操作，这时重新加载可一次文件,具体见startReloadIfChangedUnexpectedly方法。

#### 2.3.4 checkMode(mode)

```
# ContextImpl.java
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

在Android24之后的版本 SharedPreferences的mode不能再使用MODE_WORLD_READABLE和MODE_WORLD_WRITEABLE。

#### 2.3.5 getSharedPreferencesCacheLocked()

```
# ContextImpl.java
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
# SharedPreferencesImpl.java
SharedPreferencesImpl(File file, int mode) {
        mFile = file;
        mBackupFile = makeBackupFile(file);
        mMode = mode;
        mLoaded = false;
        mMap = null;
        //[见2.3.8]
        startLoadFromDisk();
    }

```

#### 2.3.7

当设置MODE_MULTI_PROCESS模式, 则每次getSharedPreferences过程, 会检查SP文件上次修改时间和文件大小, 一旦所有修改则会重新加载文件.

```

＃　SharedPreferencesImpl.java

void startReloadIfChangedUnexpectedly() {
       synchronized (mLock) {
           // TODO: wait for any pending writes to disk?
           if (!hasFileChangedUnexpectedly()) {
               return;
           }
           startLoadFromDisk();
       }
   }


   // Has the file changed out from under us?  i.e. writes that
    // we didn't instigate.
    private boolean hasFileChangedUnexpectedly() {
        synchronized (mLock) {
            if (mDiskWritesInFlight > 0) {
                // If we know we caused it, it's not unexpected.
                if (DEBUG) Log.d(TAG, "disk write in flight, not unexpected.");
                return false;
            }
        }

        final StructStat stat;
        try {
            /*
             * Metadata operations don't usually count as a block guard
             * violation, but we explicitly want this one.
             */
            BlockGuard.getThreadPolicy().onReadFromDisk();
            stat = Os.stat(mFile.getPath());
        } catch (ErrnoException e) {
            return true;
        }

        synchronized (mLock) {
            return mStatTimestamp != stat.st_mtime || mStatSize != stat.st_size;
        }
    }

```


#### 2.3.8 startLoadFromDisk()

这个方法的主要目的就是加载xml文件到mFile对象中，同时为了保证这个加载过程为异步操作，这个地方使用了线程。另外当xml文件未加载时，SharedPreferences的getString(),edit()等方法都会处于阻塞状态(阻塞和挂起的区别...）,直到mLoaded的状态变为true,后面的分析会验证这一点。

```
private void startLoadFromDisk() {
       synchronized (mLock) {
           mLoaded = false;
       }
       new Thread("SharedPreferencesImpl-load") {
           public void run() {
                //使用线程去加载xml
               loadFromDisk();
           }
       }.start();
   }


   private void loadFromDisk() {
       synchronized (mLock) {
           if (mLoaded) {
               return;
           }
           //如果容灾文件存在,则使用容灾文件
           if (mBackupFile.exists()) {
               mFile.delete();
               mBackupFile.renameTo(mFile);
           }
       }

       // Debugging
       if (mFile.exists() && !mFile.canRead()) {
           Log.w(TAG, "Attempt to read preferences file " + mFile + " without permission");
       }

       Map map = null;
       StructStat stat = null;
       try {
           stat = Os.stat(mFile.getPath());
           if (mFile.canRead()) {
               BufferedInputStream str = null;
               try {
                   str = new BufferedInputStream(
                           new FileInputStream(mFile), 16*1024);
                    //从xml中全量读取内容，保存在内存中
                   map = XmlUtils.readMapXml(str);
               } catch (Exception e) {
                   Log.w(TAG, "Cannot read " + mFile.getAbsolutePath(), e);
               } finally {
                   IoUtils.closeQuietly(str);
               }
           }
       } catch (ErrnoException e) {
           /* ignore */
       }

       synchronized (mLock) {
           mLoaded = true;
           if (map != null) {
               mMap = map;
               mStatTimestamp = stat.st_mtime;
               mStatSize = stat.st_size;
           } else {
               mMap = new HashMap<>();
           }
           mLock.notifyAll();
       }
   }

```
这样SharedPreference的实例创建已经完成了，并且我们也发现SharedPreference将从文件中读取的数据保存在了mMap的全局变量中，然后后面的读取操作其实都只是在mMap中拿数据了，下面分析获取数据和添加数据的流程。

# 3. SharedPreferences获取数据

前面的章节已经成功的创建了SharedPreferences实例，下面看看怎么使用它来获取数据，下面以getString为例分析。


## 3.1 getString()

```
@Nullable
   public String getString(String key, @Nullable String defValue) {
       synchronized (mLock) {
            //阻塞判断，需要等到数据从xml中加载到内存中，才会继续执行[见3.2]
           awaitLoadedLocked();
           //直接从内存中获取数据
           String v = (String)mMap.get(key);
           return v != null ? v : defValue;
       }
   }

```
从这里我们可以验证当我们在上文中的结论，那就是在 SharedPreferences被创建后，我们所有的读取数据都是在内存中获取的，但是这里可能就有个疑问了，加入现在我们put一条数据，是否要重新加载一次文件呢，其实在单进程中是不需要的，但是在多进程中就可能需要了。下面我们继续带着这些疑惑去寻找答案。

## 3.2 awaitLoadedLocked()

```

private void awaitLoadedLocked() {
       if (!mLoaded) {
           // Raise an explicit StrictMode onReadFromDisk for this
           // thread, since the real read will be in a different
           // thread and otherwise ignored by StrictMode.
           //[见参考文档]
           BlockGuard.getThreadPolicy().onReadFromDisk();
       }
       while (!mLoaded) {
           try {
               mLock.wait();
           } catch (InterruptedException unused) {
           }
       }
   }

从上面的操作可以看出当mLoaded为false时，也就是内容没有从xml文件中加载到内存时，该方法一直会处于阻塞状态。   


```

# 4. SharedPreferences数据添加和修改

SharedPreferences中还有个Editor和EditorImpl，它们的作用是添加数据和修改数据。但是这里要注意，我们对Editor做操作，其实只是把数据保存在Editor的一个成员变量中，真正把数据更新到SharedPreferencesImpl并且写入文件是在Editor的commit或者apply方法被调用之后.

## 4.1 EditorImpl的实现

```
＃　SharedPreferencesImpl.java

public final class EditorImpl implements Editor {
        private final Object mLock = new Object();

        @GuardedBy("mLock")
        private final Map<String, Object> mModified = Maps.newHashMap();

        @GuardedBy("mLock")
        private boolean mClear = false;

        public Editor putString(String key, @Nullable String value) {
            synchronized (mLock) {

                mModified.put(key, value);
                return this;
            }
        }
        public Editor putStringSet(String key, @Nullable Set<String> values) {
            synchronized (mLock) {
                mModified.put(key,
                        (values == null) ? null : new HashSet<String>(values));
                return this;
            }
        }
        public Editor putInt(String key, int value) {
            synchronized (mLock) {
                mModified.put(key, value);
                return this;
            }
        }
        public Editor putLong(String key, long value) {
            synchronized (mLock) {
                mModified.put(key, value);
                return this;
            }
        }
        public Editor putFloat(String key, float value) {
            synchronized (mLock) {
                mModified.put(key, value);
                return this;
            }
        }
        public Editor putBoolean(String key, boolean value) {
            synchronized (mLock) {
                mModified.put(key, value);
                return this;
            }
        }

        public Editor remove(String key) {
            synchronized (mLock) {
                mModified.put(key, this);
                return this;
            }
        }

        public Editor clear() {
            synchronized (mLock) {
                mClear = true;
                return this;
            }
        }
    }

```

从Editor的put操作来看，它是把数据添加到mModified这个成员变量中，并未写入文件。而写入的操作是在commit和apply中执行的，下面就解析 SharedPreferences中两个核心的方法commit和apply

## 4.2 commit和apply

commit和apply是Editor中的方法，实现在EditorImpl中，那么他们两有什么区别，又是怎么实现的呢？首先，他们两最大的区别是commit是一个同步方法，它有一个boolean类型的返回值，而apply是一个异步方法，没有返回值。简单理解就是，commit需要等待提交结果，而apply不需要。所以commit以牺牲一定的性能而换来准确性的提高。另外一点就是对于apply方法，官方的注释告诉我们不用担心Android组件的生命周期会对它造成的影响，底层的框架帮我们做了处理，但是真的是这样的吗？[见4.2.6]分解。下面看具体的分析。

#### 4.2.1 commit



```

# SharedPreferencesImpl.java

public boolean commit() {
           long startTime = 0;

           if (DEBUG) {
               startTime = System.currentTimeMillis();
           }
           //将数据保存在内存中[见4.2.3]
           MemoryCommitResult mcr = commitToMemory();
          //同步将数据写到硬盘中[见4.2.4]
           SharedPreferencesImpl.this.enqueueDiskWrite(
               mcr, null /* sync write on this thread okay */);
           try {
              //等待写入操作的完成
               mcr.writtenToDiskLatch.await();
           } catch (InterruptedException e) {
               return false;
           } finally {
               if (DEBUG) {
                   Log.d(TAG, mFile.getName() + ":" + mcr.memoryStateGeneration
                           + " committed after " + (System.currentTimeMillis() - startTime)
                           + " ms");
               }
           }
           //用于onSharedPreferenceChanged的回调提醒
           notifyListeners(mcr);
           return mcr.writeToDiskResult;
       }


```
在commit中首先调用commitToMemory将数据保存在内存中，然后会执行写入操作，并且让当前commit所在的线程处于阻塞状态。当写入完成后会通过onSharedPreferenceChanged提醒数据发生的变化。这个过程中有个注意的地方，　mcr.writtenToDiskLatch.await()，如果非并发调用commit方法，这个操作是不需要的，但是如果并发commit时，就必须有mcr.writtenToDiskLatch.await()操作了，因为写入操作可能会被放到别的子线程中执行.然后就是notifyListeners()方法，当我们写入的数据发生变化后给我们的回调，这个回调我们可以通过注册下面的代码拿到。

```
sp.registerOnSharedPreferenceChangeListener { sharedPreferences, key -> }

```

#### 4.2.2 apply


```
# SharedPreferencesImpl.java
public void apply() {
          final long startTime = System.currentTimeMillis();
          //将数据保存在内存中[见4.2.3]
          final MemoryCommitResult mcr = commitToMemory();
          final Runnable awaitCommit = new Runnable() {
                  public void run() {
                      try {
                          mcr.writtenToDiskLatch.await();
                      } catch (InterruptedException ignored) {
                      }

                      if (DEBUG && mcr.wasWritten) {
                          Log.d(TAG, mFile.getName() + ":" + mcr.memoryStateGeneration
                                  + " applied after " + (System.currentTimeMillis() - startTime)
                                  + " ms");
                      }
                  }
              };

          QueuedWork.addFinisher(awaitCommit);

          Runnable postWriteRunnable = new Runnable() {
                  public void run() {
                      awaitCommit.run();
                      QueuedWork.removeFinisher(awaitCommit);
                  }
              };

        　// 执行文件写入操作，传入的 postWriteRunnable 参数不为 null，所以在                 
          // enqueueDiskWrite 方法中会开启子线程异步将数据写入文件
          SharedPreferencesImpl.this.enqueueDiskWrite(mcr, postWriteRunnable);

          // Okay to notify the listeners before it's hit disk
          // because the listeners should always get the same
          // SharedPreferences instance back, which has the
          // changes reflected in memory.
          notifyListeners(mcr);
      }

```
apply方法的流程和commit其实是差不多，但是apply的写入操作会被放在一个单独的线程中执行，并且不会阻塞当前apply所在的线程。当时有中特殊的请求是会阻塞的，那就是在Activity的onStop方法被调用，并且apply的写入操作还未完成时，会阻塞主线程，更详情的分析[见4.2.6]


#### 4.2.3 commitToMemory


```
# SharedPreferencesImpl.java

private MemoryCommitResult commitToMemory() {
           long memoryStateGeneration;
           List<String> keysModified = null;
           Set<OnSharedPreferenceChangeListener> listeners = null;
           Map<String, Object> mapToWriteToDisk;

           synchronized (SharedPreferencesImpl.this.mLock) {
               // We optimistically don't make a deep copy until
               // a memory commit comes in when we're already
               // writing to disk.
               if (mDiskWritesInFlight > 0) {
                   // We can't modify our mMap as a currently
                   // in-flight write owns it.  Clone it before
                   // modifying it.
                   // noinspection unchecked
                   mMap = new HashMap<String, Object>(mMap);
               }
               mapToWriteToDisk = mMap;
               mDiskWritesInFlight++;

               boolean hasListeners = mListeners.size() > 0;
               if (hasListeners) {
                   keysModified = new ArrayList<String>();
                   listeners = new HashSet<OnSharedPreferenceChangeListener>(mListeners.keySet());
               }

               synchronized (mLock) {
                   boolean changesMade = false;

                   if (mClear) {
                       if (!mMap.isEmpty()) {
                           changesMade = true;
                           mMap.clear();
                       }
                       mClear = false;
                   }
                    //mModified 保存的写记录同步到内存中的 mMap 中
                   for (Map.Entry<String, Object> e : mModified.entrySet()) {
                       String k = e.getKey();
                       Object v = e.getValue();
                       // "this" is the magic value for a removal mutation. In addition,
                       // setting a value to "null" for a given key is specified to be
                       // equivalent to calling remove on that key.
                       if (v == this || v == null) {
                           if (!mMap.containsKey(k)) {
                               continue;
                           }
                           mMap.remove(k);
                       } else {
                           if (mMap.containsKey(k)) {
                               Object existingValue = mMap.get(k);
                               if (existingValue != null && existingValue.equals(v)) {
                                   continue;
                               }
                           }
                           mMap.put(k, v);
                       }

                       changesMade = true;
                       if (hasListeners) {
                           keysModified.add(k);
                       }
                   }

                 // 将 mModified 同步到 mMap 之后，清空 mModified
                   mModified.clear();

                   if (changesMade) {
                       mCurrentMemoryStateGeneration++;
                   }

                   memoryStateGeneration = mCurrentMemoryStateGeneration;
               }
           }
           return new MemoryCommitResult(memoryStateGeneration, keysModified, listeners,
                   mapToWriteToDisk);
       }

```
通过上面的注释和代码，我们了解到每次有写操作的时候，都会同步mMap,这样我们就不需要每次在读取的时候重新load文件了，但是这个结论在多进程中不适用。另外需要关注的是mDiskWritesInFlight这个变量，当mDiskWritesInFlight大于0时，会拷贝一份mMap，把它存到MemoryCommitResult类的成员mapToWriteToDisk中，然后再把mDiskWritesInFlight加1。在把mapToWriteDisk写入到文件后，mDiskWritesInFlight会减1，所以mDiskWritesInFlight大于0说明之前已经有调用过commitToMemory了，并且还没有把map写入到文件，这样前后两次要准备写入文件的mapToWriteToDisk是两个不同的内存对象，后一次调用commitToMemory时，再更新mMap中的值时不会影响前一次的mapToWriteToDisk的写入文件



#### 4.2.4 enqueueDiskWrite


```
# SharedPreferencesImpl.java

private void enqueueDiskWrite(final MemoryCommitResult mcr,
                                 final Runnable postWriteRunnable) {
       final boolean isFromSyncCommit = (postWriteRunnable == null);

       // 创建Runnable，负责将数据接入文件
       final Runnable writeToDiskRunnable = new Runnable() {
               public void run() {
                   synchronized (mWritingToDiskLock) {
                      //写入文件操作[见4.2.5]
                       writeToFile(mcr, isFromSyncCommit);
                   }
                   synchronized (mLock) {

                     // 写入文件后将mDiskWritesInFlight值减一
                       mDiskWritesInFlight--;
                   }
                   if (postWriteRunnable != null) {
                       postWriteRunnable.run();
                   }
               }
           };

       // Typical #commit() path with fewer allocations, doing a write on
       // the current thread.
       if (isFromSyncCommit) {
           boolean wasEmpty = false;
           synchronized (mLock) {
               wasEmpty = mDiskWritesInFlight == 1;
           }
           if (wasEmpty) {

             // 当只有一个 commit 请求未处理，那么无需开启线程进行处理，直接在本线程执行 //writeToDiskRunnable 即可
               writeToDiskRunnable.run();
               return;
           }
       }
       //单线程执行写入操作
       QueuedWork.queue(writeToDiskRunnable, !isFromSyncCommit);
   }

```
从这里我们可以得出commit操作，如果只有一次操作的时候，只会在当前线程中执行，但是如果并发commit时，剩余的writeToDiskRunnable则会被放在单独的线程中执行，而第一次commit所在的线程则进入阻塞状态。它需要等后面的commit都成功后才能算真正的成功，而返回的状态也是最后一次commit的状态。

#### 4.2.5 writeToFile

终于，迎来了最后真正的写操作，包括在写入成功的时候将容灾文件删除，或者在写入失败时将半成品文件删除等，最后将写结果保存在MemoryCommitResult中。

```
# SharedPreferencesImpl.java

// Note: must hold mWritingToDiskLock
   private void writeToFile(MemoryCommitResult mcr, boolean isFromSyncCommit) {
       long startTime = 0;
       long existsTime = 0;
       long backupExistsTime = 0;
       long outputStreamCreateTime = 0;
       long writeTime = 0;
       long fsyncTime = 0;
       long setPermTime = 0;
       long fstatTime = 0;
       long deleteTime = 0;

       if (DEBUG) {
           startTime = System.currentTimeMillis();
       }

       boolean fileExists = mFile.exists();

       if (DEBUG) {
           existsTime = System.currentTimeMillis();

           // Might not be set, hence init them to a default value
           backupExistsTime = existsTime;
       }

       // Rename the current file so it may be used as a backup during the next read
       if (fileExists) {
           boolean needsWrite = false;

           // Only need to write if the disk state is older than this commit
           if (mDiskStateGeneration < mcr.memoryStateGeneration) {
               if (isFromSyncCommit) {
                   needsWrite = true;
               } else {
                   synchronized (mLock) {
                       // No need to persist intermediate states. Just wait for the latest state to
                       // be persisted.
                       if (mCurrentMemoryStateGeneration == mcr.memoryStateGeneration) {
                           needsWrite = true;
                       }
                   }
               }
           }

           if (!needsWrite) {
               mcr.setDiskWriteResult(false, true);
               return;
           }

           boolean backupFileExists = mBackupFile.exists();

           if (DEBUG) {
               backupExistsTime = System.currentTimeMillis();
           }

           if (!backupFileExists) {
               if (!mFile.renameTo(mBackupFile)) {
                   Log.e(TAG, "Couldn't rename file " + mFile
                         + " to backup file " + mBackupFile);
                   mcr.setDiskWriteResult(false, false);
                   return;
               }
           } else {
               mFile.delete();
           }
       }

       // Attempt to write the file, delete the backup and return true as atomically as
       // possible.  If any exception occurs, delete the new file; next time we will restore
       // from the backup.
       try {
           FileOutputStream str = createFileOutputStream(mFile);

           if (DEBUG) {
               outputStreamCreateTime = System.currentTimeMillis();
           }

           if (str == null) {
               mcr.setDiskWriteResult(false, false);
               return;
           }
           XmlUtils.writeMapXml(mcr.mapToWriteToDisk, str);

           writeTime = System.currentTimeMillis();

           FileUtils.sync(str);

           fsyncTime = System.currentTimeMillis();

           str.close();
           ContextImpl.setFilePermissionsFromMode(mFile.getPath(), mMode, 0);

           if (DEBUG) {
               setPermTime = System.currentTimeMillis();
           }

           try {
               final StructStat stat = Os.stat(mFile.getPath());
               synchronized (mLock) {
                   mStatTimestamp = stat.st_mtime;
                   mStatSize = stat.st_size;
               }
           } catch (ErrnoException e) {
               // Do nothing
           }

           if (DEBUG) {
               fstatTime = System.currentTimeMillis();
           }

           // Writing was successful, delete the backup file if there is one.
           mBackupFile.delete();

           if (DEBUG) {
               deleteTime = System.currentTimeMillis();
           }

           mDiskStateGeneration = mcr.memoryStateGeneration;

           mcr.setDiskWriteResult(true, true);

           if (DEBUG) {
               Log.d(TAG, "write: " + (existsTime - startTime) + "/"
                       + (backupExistsTime - startTime) + "/"
                       + (outputStreamCreateTime - startTime) + "/"
                       + (writeTime - startTime) + "/"
                       + (fsyncTime - startTime) + "/"
                       + (setPermTime - startTime) + "/"
                       + (fstatTime - startTime) + "/"
                       + (deleteTime - startTime));
           }

           long fsyncDuration = fsyncTime - writeTime;
           mSyncTimes.add(Long.valueOf(fsyncDuration).intValue());
           mNumSync++;

           if (DEBUG || mNumSync % 1024 == 0 || fsyncDuration > MAX_FSYNC_DURATION_MILLIS) {
               mSyncTimes.log(TAG, "Time required to fsync " + mFile + ": ");
           }

           return;
       } catch (XmlPullParserException e) {
           Log.w(TAG, "writeToFile: Got exception:", e);
       } catch (IOException e) {
           Log.w(TAG, "writeToFile: Got exception:", e);
       }

       // Clean up an unsuccessfully written file
       if (mFile.exists()) {
           if (!mFile.delete()) {
               Log.e(TAG, "Couldn't clean up partially-written file " + mFile);
           }
       }
       mcr.setDiskWriteResult(false, false);
   }

```
#### 4.2.6 apply引起的anr

还记得在介绍apply时，我们了解到apply是异步的，不会阻塞我们的主线程，官方的注释页说过android组件的生命周期不会对aplly的异步写入造成影响，告诉我们不用担心，但它却会有一定的几率引起anr,比如有一种情况，当我们的Activity执行onPause()的时候，也就是ActivityThread类执行handleStopActivity方法是，看看它干了啥
它会执行  QueuedWork.waitToFinish()方法，而waitToFinish方法中有个while循环，如果我们还有没有完成的异步落盘操作时，它会调用到我们在apply方法中创建的awaitCommit，让我们主线程处于等待状态，直到所有的落盘操作完成，才会跳出循环，这也就是apply造成anr的元凶。


```
# ActivityThread.java

@Override
  public void handleStopActivity(IBinder token, boolean show, int configChanges,
          PendingTransactionActions pendingActions, boolean finalStateRequest, String reason) {
      //...省略

      // Make sure any pending writes are now committed.
      if (!r.isPreHoneycomb()) {
          QueuedWork.waitToFinish();
      }
     //...省略
  }

```



```
/**
   * Trigger queued work to be processed immediately. The queued work is processed on a separate
   * thread asynchronous. While doing that run and process all finishers on this thread. The
   * finishers can be implemented in a way to check weather the queued work is finished.
   *
   * Is called from the Activity base class's onPause(), after BroadcastReceiver's onReceive,
   * after Service command handling, etc. (so async work is never lost)
   */
  public static void waitToFinish() {
      ...省略
      try {
          while (true) {
              Runnable finisher;

              synchronized (sLock) {
                  finisher = sFinishers.poll();
              }

              if (finisher == null) {
                  break;
              }
              [见4.2.2中的awaitCommit]  
              finisher.run();
          }
      } finally {
          sCanDelay = true;
      }
      ...省略
  }


```

# 总结

SharedPreferences是一种轻量级的存储方式，使用方便，但是也有它适用的场景。要优雅滴使用sp，要注意以下几点：

1. 不同的配置信息不要都放在一起，这样每次读写会越来越卡。
2. 不要在同一个文件中频繁的读取key和value，因为同步锁的缘故，会造成卡顿
3. 不要频繁的commit和apply，尽量批量修改一次提交，尤其是apply,会造成anr
4. 不要在保存太大的数据
5. 不要指望它在多进程中使用。


# 参考文献

1. [SharedPreference的读写原理分析](https://blog.csdn.net/yueqian_scut/article/details/51477760)

2. [一眼看穿 SharedPreferences](https://mp.weixin.qq.com/s?__biz=Mzg5NjAzMjI0NQ==&mid=2247483824&idx=2&sn=72394553884d9d8e5560827844f1c690&chksm=c0060d2af771843c545c182d0bd0d0fa81a8ff376c062bb3f851325f904606301ce164602d93&mpshare=1&scene=1&srcid=0112eAzgdwYIPDzeECLHlio6&key=d1dd5c9a0a50c21a8507dbe6b90e9de2a89469b9fcd128ba4cfe412441ae8d96e67716c6d09a4a4ad00e8e39dc0554d1f157fd4f4097dffdee8e9f87745ce8202f13628b3ffa0d8c35a3cba7faae82ee&ascene=1&uin=MjQ5MDc1NzIzNg%3D%3D&devicetype=Windows+7&version=62060739&lang=zh_CN&pass_ticket=4JbX2ifmV0NW9DMLlRiASBNbvz%2BRLdiJVJu61suZm60%2FZ2OtpX1JT2DDnIPgHEl%2B)

3. [彻底搞懂 SharedPreferences](https://juejin.im/entry/597446ed6fb9a06bac5bc630)

4. [StrictMode解析](http://duanqz.github.io/2015-11-04-StrictMode-Analysis#23-strictmode-penalty)
