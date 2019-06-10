> “A small leak will sink a great ship.” - Benjamin Franklin



## 煤矿中的金丝雀

故事发生在工业革命后的英国，有经验的煤矿工人都会在煤矿巷道中放几只金丝雀，当瓦斯气体超标时，金丝雀会很快死掉，这样煤矿工人能提前得到预警，提前离开巷道。金丝雀的英文名就叫Carary，此后人民把煤矿中的金丝雀作为危险预警的代名词。

> canary in a coal mine


## LeakCanary

回到我们今天的主题，在平时Android开发中，稍不注意就会写出内存泄漏的代码，有些甚至带到了生产环境而我们却浑然不知。是否我们能找一只煤矿中的金丝雀呢，让他监视着我们的代码，及时发现内存的风险。基于上面的需求LeakCanary就粉墨登场了。


## 集成LeakCanary

集成LeakCarary其实非常的简单，看看官方的例子

```

public class ExampleApplication extends Application {
  @Override public void onCreate() {
    super.onCreate();
    setupLeakCanary();
  }

  protected void setupLeakCanary() {
    enabledStrictMode();
    if (LeakCanary.isInAnalyzerProcess(this)) {
      // 堆文件的分析是在一个独立的进程中，所以不应该走应用初始化的逻辑      
      return;
    }
    LeakCanary.install(this);
  }

  private static void enabledStrictMode() {
    StrictMode.setThreadPolicy(new StrictMode.ThreadPolicy.Builder() //
        .detectAll() //
        .penaltyLog() //
        .penaltyDeath() //
        .build());
  }
}
1


```

## LeakCanary.install()方法

上面看到了LeakCanary集成的方法，很简单，就调用了install方法。


```
/**
   * Creates a {@link RefWatcher} that works out of the box, and starts watching activity
   * references (on ICS+).
   */
  public static @NonNull RefWatcher install(@NonNull Application application) {
    return refWatcher(application).listenerServiceClass(DisplayLeakService.class)
        .excludedRefs(AndroidExcludedRefs.createAppDefaults().build())
        .buildAndInstall();
  }

```

总结一下install方法的主要作用：

1. 创建了一个AndroidRefWatcherBuilder对象，一看这个类名就知道它使用了构建者模式，接下来就是这个给这个Builder添加种种配置。
2. 第一个配置listenerServiceClass，它要求我们传入一个Class类型的Service,其作用是打印我们的leak的信息，并且在通知栏里发出消息，当然了假如我们需要自己处理leak的信息，比如将其上传到服务器，就可以复写这里的
DisplayLeakService，在其afterDefaultHandling方法中做相关的逻辑。

3. excludedRefs 配置的是我们要过滤的内存泄漏信息，比如Android自己的源码中，或者一些手机厂商自定义的rom中存在的内存泄漏，我们是不关心的，或者无能无力的，我们不想让这部分的内存泄漏出现在我们的结果列表中，就需要配置这个选项，当然LeakCanary已经默认了一个已知的列表。当然了你也可以自定义这个列表。

4. 接下来就调用buildAndInstall方法，返回一个RefWatcher对象。



## AndroidRefWatcherBuilder.buildAndInstall()方法

```

  /**
   *  开始监测activity和activity的引用
   */
  public @NonNull RefWatcher buildAndInstall() {
    if (LeakCanaryInternals.installedRefWatcher != null) {
      throw new UnsupportedOperationException("buildAndInstall() should only be called once.");
    }
    //构建RefWatcher，实现了很多的默认配置
    RefWatcher refWatcher = build();
    if (refWatcher != DISABLED) {
      if (enableDisplayLeakActivity) {
        LeakCanaryInternals.setEnabledAsync(context, DisplayLeakActivity.class, true);
      }
      if (watchActivities) {
        //在application中registerActivityLifecycleCallbacks，当activity Destroy的时候
        //将activity的引用保存在RefWatcher的软引用中
        ActivityRefWatcher.install(context, refWatcher);
      }
      if (watchFragments) {
        FragmentRefWatcher.Helper.install(context, refWatcher);
      }
    }
    LeakCanaryInternals.installedRefWatcher = refWatcher;
    return refWatcher;
  }


```

该方法总结：


1. 构建RefWatcher，实现了很多的默认设置
2. 通过ActivityRefWatcher.install方法在application中registerActivityLifecycleCallbacks，当activity Destroy的时候，将activity的引用保存在RefWatcher的软引用中。
3. 通过FragmentRefWatcher.Helper.install方法监测fragment的引用。


## ActivityRefWatcher.install

下面以activity为例，讲解整个流程，fragment的检测和activity类似。在该方法中主要的操作就是上面所说的registerActivityLifecycleCallbacks了，而检测的开始是从Activity调用OnDestroy的时候开始。

```

public static void install(@NonNull Context context, @NonNull RefWatcher refWatcher) {
    Application application = (Application) context.getApplicationContext();
    ActivityRefWatcher activityRefWatcher = new ActivityRefWatcher(application, refWatcher);

    application.registerActivityLifecycleCallbacks(activityRefWatcher.lifecycleCallbacks);
  }


```

```
private final Application.ActivityLifecycleCallbacks lifecycleCallbacks =
      new ActivityLifecycleCallbacksAdapter() {
        @Override public void onActivityDestroyed(Activity activity) {
          refWatcher.watch(activity);
        }
      };


```

## RefWatcher.watch


当onActivityDestroyed被系统调用的时候，RefWatcher调用了它的watch方法，并将activity的引用传入。watch方法中做了下面几件事：

1. 生成一个唯一的uuid保存在retainedKeys这个set中
2. 将activity的引用保存在一个弱引用中
3. 调用ensureGoneAsync方法，通过方法名可以猜测他的作用是确保activity已经被垃圾回收，下面我们会仔细分析这个过程


对弱引用不熟悉的读者，这里要注意一下KeyedWeakReference这个类，它实际上是继承的WeakReference，WeakReference有个两个参数的构造方法，第一个参数是当前的引用，这个很好理解，另外一个是一个队列，它的作用是当当前对象被垃圾回收后，会将其注册在这个队列中。我们在分析ensureGoneAsync方法的时候会用到这个知识点。


```
public void watch(Object watchedReference) {
    watch(watchedReference, "");
  }


```

```

public void watch(Object watchedReference, String referenceName) {
    if (this == DISABLED) {
      return;
    }
    checkNotNull(watchedReference, "watchedReference");
    checkNotNull(referenceName, "referenceName");
    final long watchStartNanoTime = System.nanoTime();
    String key = UUID.randomUUID().toString();
    retainedKeys.add(key);
    final KeyedWeakReference reference =
        new KeyedWeakReference(watchedReference, key, referenceName, queue);

    ensureGoneAsync(watchStartNanoTime, reference);
  }

```


## RefWatcher.ensureGoneAsync

```
private void ensureGoneAsync(final long watchStartNanoTime, final KeyedWeakReference reference) {
    watchExecutor.execute(new Retryable() {
      @Override public Retryable.Result run() {
        return ensureGone(reference, watchStartNanoTime);
      }
    });
  }

  @SuppressWarnings("ReferenceEquality") // Explicitly checking for named null.
  Retryable.Result ensureGone(final KeyedWeakReference reference, final long watchStartNanoTime) {
    long gcStartNanoTime = System.nanoTime();
    long watchDurationMs = NANOSECONDS.toMillis(gcStartNanoTime - watchStartNanoTime);

    //将已经回收的对象从retainedKeys中清除
    removeWeaklyReachableReferences();
    //debug模式不进行检测
    if (debuggerControl.isDebuggerAttached()) {
      // The debugger can create false leaks.
      return RETRY;
    }
    //已经回收
    if (gone(reference)) {
      return DONE;
    }
    //强制进行垃圾回收
    gcTrigger.runGc();
    //再次将已经回收的对象从retainedKeys中移除
    removeWeaklyReachableReferences();
    //如果还没有回收那么就认为发生了内存泄漏，dump heap文件，并进行分析
    if (!gone(reference)) {
      long startDumpHeap = System.nanoTime();
      long gcDurationMs = NANOSECONDS.toMillis(startDumpHeap - gcStartNanoTime);

      File heapDumpFile = heapDumper.dumpHeap();
      if (heapDumpFile == RETRY_LATER) {
        // Could not dump the heap.
        return RETRY;
      }
      long heapDumpDurationMs = NANOSECONDS.toMillis(System.nanoTime() - startDumpHeap);

      HeapDump heapDump = heapDumpBuilder.heapDumpFile(heapDumpFile).referenceKey(reference.key)
          .referenceName(reference.name)
          .watchDurationMs(watchDurationMs)
          .gcDurationMs(gcDurationMs)
          .heapDumpDurationMs(heapDumpDurationMs)
          .build();

      heapdumpListener.analyze(heapDump);
    }
    return DONE;
  }

```

总结一下上面的流程，首先判断当前引用对象有没有被回收，如果没有被回收则强制虚拟机进行一次gc，之后再判断该引用对象是否被回收，如果还没有，则认为发生了内存泄漏，dump Heap文件，并且对其进行分析。




## 参考文献

- [理解Java中的弱引用](https://www.cnblogs.com/absfree/p/5555687.html)



















