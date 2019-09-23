> “A small leak will sink a great ship.” - Benjamin Franklin



## 煤矿中的金丝雀

故事发生在工业革命后的英国，有经验的煤矿工人都会在煤矿巷道中放几只金丝雀，当瓦斯气体超标时，金丝雀会很快死掉，这样煤矿工人能提前得到预警，离开巷道。金丝雀的英文名就叫Canary，此后人们把煤矿中的金丝雀作为危险预警的代名词。

> canary in a coal mine


## LeakCanary

回到我们今天的主题，在平时Android开发中，稍不注意就会写出内存泄漏的代码，有些甚至带到了生产环境而我们却浑然不知。是否我们能找一只煤矿中的金丝雀呢，让他监视着我们的代码，及时发现内存泄漏的风险。基于上面的需求LeakCanary就粉墨登场了。


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

## LeakCanary.install

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

1. 创建了一个AndroidRefWatcherBuilder对象，一看这个类名就知道它使用了构建者模式，接下来就是给这个Builder添加种种配置。
2. 第一个配置listenerServiceClass，它要求我们传入一个Class类型的Service,其作用是打印我们的leak的信息，并且在通知栏里发出消息，当然了假如我们需要自己处理leak信息，比如将其上传到服务器，就可以复写这里的
DisplayLeakService，在其afterDefaultHandling方法中做相关的逻辑。

3. excludedRefs 配置的是我们要过滤的内存泄漏信息，比如Android自己的源码中，或者一些手机厂商自定义的rom中存在的内存泄漏，我们是不关心的，或者无能无力，我们不想让这部分的内存泄漏出现在我们的结果列表中，就需要配置这个选项，当然LeakCanary已经默认了一个已知的列表。当然了你也可以自定义这个列表。

4. 接下来就调用buildAndInstall方法，返回一个RefWatcher对象。



## AndroidRefWatcherBuilder.buildAndInstall

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

下面以activity为例，讲解整个流程，fragment的检测和activity类似。在该方法中主要的操作就是上面所说的registerActivityLifecycleCallbacks了，而检测是从Activity的onDestroy方法被调用开始。

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

      //dump heap信息到指定的文件中
      File heapDumpFile = heapDumper.dumpHeap();
      if (heapDumpFile == RETRY_LATER) {
        // Could not dump the heap.
        return RETRY;
      }
      long heapDumpDurationMs = NANOSECONDS.toMillis(System.nanoTime() - startDumpHeap);

      //保存heap dump中的信息，比如hprof文件、发生内存泄漏的引用、从watch到gc的时间间隔、gc所花的时间、heap dump所花的时间等
      HeapDump heapDump = heapDumpBuilder.heapDumpFile(heapDumpFile).referenceKey(reference.key)
          .referenceName(reference.name)
          .watchDurationMs(watchDurationMs)
          .gcDurationMs(gcDurationMs)
          .heapDumpDurationMs(heapDumpDurationMs)
          .build();
       //启动一个单独进程的service去分析heap dump的结果     
      heapdumpListener.analyze(heapDump);
    }
    return DONE;
  }

```

总结一下上面的流程，首先判断当前引用对象有没有被回收，如果没有被回收则强制虚拟机进行一次gc，之后再判断该引用对象是否被回收，如果还没有，则认为发生了内存泄漏，dump Heap文件，并且对其进行分析。


## RefWatcher.removeWeaklyReachableReferences

还记得我们上面创建弱引用时，传入了一个弱引用队列，这个队列中存放着就是已经被回收的对象的引用。通过这个队列，保证retainedKeys中存放的key值对应的引用都是没有被gc回收的。


```

private void removeWeaklyReachableReferences() {
    // WeakReferences are enqueued as soon as the object to which they point to becomes weakly
    // reachable. This is before finalization or garbage collection has actually happened.
    KeyedWeakReference ref;
    while ((ref = (KeyedWeakReference) queue.poll()) != null) {
      retainedKeys.remove(ref.key);
    }
  }


```

## AndroidHeapDumper.dumpHeap

该方法的作用是dump heap信息到指定的文件中

```

@SuppressWarnings("ReferenceEquality") // Explicitly checking for named null.
  @Override @Nullable
  public File dumpHeap() {

    //创建一个文件，永远存放drump 的heap信息
    File heapDumpFile = leakDirectoryProvider.newHeapDumpFile();

    if (heapDumpFile == RETRY_LATER) {
      return RETRY_LATER;
    }

    FutureResult<Toast> waitingForToast = new FutureResult<>();
    showToast(waitingForToast);

    if (!waitingForToast.wait(5, SECONDS)) {
      CanaryLog.d("Did not dump heap, too much time waiting for Toast.");
      return RETRY_LATER;
    }

    Notification.Builder builder = new Notification.Builder(context)
        .setContentTitle(context.getString(R.string.leak_canary_notification_dumping));
    Notification notification = LeakCanaryInternals.buildNotification(context, builder);
    NotificationManager notificationManager =
        (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
    int notificationId = (int) SystemClock.uptimeMillis();
    notificationManager.notify(notificationId, notification);

    Toast toast = waitingForToast.get();
    try {
      //dump heap信息到刚才创建的文件中
      Debug.dumpHprofData(heapDumpFile.getAbsolutePath());
      cancelToast(toast);
      notificationManager.cancel(notificationId);
      return heapDumpFile;
    } catch (Exception e) {
      CanaryLog.d(e, "Could not dump heap");
      // Abort heap dump
      return RETRY_LATER;
    }
  }



```

## ServiceHeapDumpListener.analyze

对dump到的heap信息进行分析是在一个独立进程的Service中完成的。

```

@Override public void analyze(@NonNull HeapDump heapDump) {
    checkNotNull(heapDump, "heapDump");
    HeapAnalyzerService.runAnalysis(context, heapDump, listenerServiceClass);
  }


```

```

public static void runAnalysis(Context context, HeapDump heapDump,
      Class<? extends AbstractAnalysisResultService> listenerServiceClass) {
    setEnabledBlocking(context, HeapAnalyzerService.class, true);
    setEnabledBlocking(context, listenerServiceClass, true);
    Intent intent = new Intent(context, HeapAnalyzerService.class);
    intent.putExtra(LISTENER_CLASS_EXTRA, listenerServiceClass.getName());
    intent.putExtra(HEAPDUMP_EXTRA, heapDump);
    ContextCompat.startForegroundService(context, intent);
  }


```


## HeapAnalyzerService.onHandleIntentInForeground


```

@Override protected void onHandleIntentInForeground(@Nullable Intent intent) {
    if (intent == null) {
      CanaryLog.d("HeapAnalyzerService received a null intent, ignoring.");
      return;
    }
    String listenerClassName = intent.getStringExtra(LISTENER_CLASS_EXTRA);
    HeapDump heapDump = (HeapDump) intent.getSerializableExtra(HEAPDUMP_EXTRA);

    HeapAnalyzer heapAnalyzer =
        new HeapAnalyzer(heapDump.excludedRefs, this, heapDump.reachabilityInspectorClasses);
    //分析heap dump，返回结果
    AnalysisResult result = heapAnalyzer.checkForLeak(heapDump.heapDumpFile, heapDump.referenceKey,
        heapDump.computeRetainedHeapSize);
     //启动一个新的Service用于处理返回的分析结果 
    AbstractAnalysisResultService.sendResultToListener(this, listenerClassName, heapDump, result);
  }

```

可见这里仍然不是真正的分析处理heap dump的地方，继续往下找。


## HeapAnalyzer.checkForLeak

终于终于我们来到了最终分析heap dump的地方，这个方法的主要的作用通过分析heap dump,找到我们发生内存泄漏的引用，然后计算出到GCRoot最短的引用链。对heap dump的分析leakcanary使用了著名的[haha库](https://github.com/square/haha), 不过最新的版本的leakcanary已经自己实现了[heap dump的分析](https://github.com/square/leakcanary/tree/master/leakcanary-haha)。


```

/**
   * Searches the heap dump for a {@link KeyedWeakReference} instance with the corresponding key,
   * and then computes the shortest strong reference path from that instance to the GC roots.
   */
  public @NonNull AnalysisResult checkForLeak(@NonNull File heapDumpFile,
      @NonNull String referenceKey,
      boolean computeRetainedSize) {
    long analysisStartNanoTime = System.nanoTime();

    if (!heapDumpFile.exists()) {
      Exception exception = new IllegalArgumentException("File does not exist: " + heapDumpFile);
      return failure(exception, since(analysisStartNanoTime));
    }

    try {
      listener.onProgressUpdate(READING_HEAP_DUMP_FILE);
      HprofBuffer buffer = new MemoryMappedFileBuffer(heapDumpFile);
      HprofParser parser = new HprofParser(buffer);
      listener.onProgressUpdate(PARSING_HEAP_DUMP);
      Snapshot snapshot = parser.parse();
      listener.onProgressUpdate(DEDUPLICATING_GC_ROOTS);
      deduplicateGcRoots(snapshot);
      listener.onProgressUpdate(FINDING_LEAKING_REF);
      Instance leakingRef = findLeakingReference(referenceKey, snapshot);

      // False alarm, weak reference was cleared in between key check and heap dump.
      if (leakingRef == null) {
        String className = leakingRef.getClassObj().getClassName();
        return noLeak(className, since(analysisStartNanoTime));
      }
      return findLeakTrace(analysisStartNanoTime, snapshot, leakingRef, computeRetainedSize);
    } catch (Throwable e) {
      return failure(e, since(analysisStartNanoTime));
    }
  }


```


## Q&A

1. LeakCanary中强制gc的方式

这段代码是LeakCanary中采用Android系统源码实现强制gc的方式

```

 GcTrigger DEFAULT = new GcTrigger() {
    @Override public void runGc() {
      // Code taken from AOSP FinalizationTest:
      // https://android.googlesource.com/platform/libcore/+/master/support/src/test/java/libcore/
      // java/lang/ref/FinalizationTester.java
      // System.gc() does not garbage collect every time. Runtime.gc() is
      // more likely to perform a gc.
      Runtime.getRuntime().gc();
      enqueueReferences();
      System.runFinalization();
    }

    private void enqueueReferences() {
      // Hack. We don't have a programmatic way to wait for the reference queue daemon to move
      // references to the appropriate queues.
      try {
        Thread.sleep(100);
      } catch (InterruptedException e) {
        throw new AssertionError();
      }
    }
  };


```

但是问题来了，为什么这种方式可以实现强制gc，我的结论是(没有经过验证)虚拟机执行gc的时候，回收的对象需要经历两次标记才能被真正的回收。执行完第一次标记后，虚拟机会判断对象是否复写了finalize()方法，或者是否执行过finalize,如果符合其中一个条件则，不会执行finalize方法。如果被判定需要执行finalize()方法,虚拟机会将该对象加入到名为F-Queue的队列中，并且在一个优先级底的线程中执行对象的finallize()方法。所以需要让线程sleep一会，目的就是等待finallize的执行。之后执行第二次标记，这个时候如果对象没有在finallize中复活，则该对象就会被回收。



## 总结

上面已经把LeakCanary的整体流程分析完了，但是由于作者的水平有限，很多细节方面的东西可能没有顾忌到，比如heap dump分析那块的东西其实是很重要的一个部分，如果大家有兴趣，可以着重的看一下。好了,这篇文章就写到这里了。






## 参考文献

- [理解Java中的弱引用](https://www.cnblogs.com/absfree/p/5555687.html)























