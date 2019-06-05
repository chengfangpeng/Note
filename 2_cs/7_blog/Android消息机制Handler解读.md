

> 本文基于Android源码8.1





## 概述

在Android系统中使用了很多种通信的方式，比如进程间通信使用的Socket,Binder机制等，但是在相同进程不同线程之间通信再使用这些方式就显得杀鸡用牛了，于是Android使用了一种新的Handler消息机制，有了它我们可以很方便的进行不同线程之间的通信，当然了Handler消息机制也只能限定在同一个进程中。但是，Android系统中关于Handler消息机制的使用却不限于此，比如:android的四大组件，事件机制等都和Handler消息机制密切相关。我们所说的Handler消息机制是由Looper、MessageQueue、Message、Handler等类共同组成的，接下来就通过源码研究一下handler消息机制的原理。话不多说，先上张图，下图虽然简单，但是它体现了handler消息机制最核心的运行流程，在接下来枯燥而乏味的源码解读中，大家可以结合这张图去看，思路可能会更清晰些。



![如图](assets/handler_1.png)





## Handler实例

下面先看一个我们平时使用handler的例子，通过这个这个例子，我们一步一步去探究handler机制的整个运行的流程。这个例子就是怎么在一个线程中创建Handler,可以简单概括为下面的步骤:

1. 调用Looper.prepare()方法
2. 创建Handler对象
3. 调用Looper.loop()方法
4. 调用Looper的quit方法结束loop


```
private void handlerTest(){

       mLooperThread = new LooperThread("xray");
       mLooperThread.start();
       findViewById(R.id.btn_send_msg).setOnClickListener(new View.OnClickListener() {
           @Override
           public void onClick(View v) {
               mLooperThread.mHandler.sendEmptyMessage(10);
           }
       });


   }

   class LooperThread extends Thread{

       public Handler mHandler;

       public LooperThread(String name) {
           super(name);
       }

       @Override
       public void run() {
           super.run();

           Looper.prepare();

           mHandler = new Handler(){
               @Override
               public void handleMessage(Message msg) {
                   super.handleMessage(msg);
                   Log.d(TAG, "looperThread thread id = " + Thread.currentThread().getId());
               }
           };
           Looper.loop();
       }
   }

   @Override
   protected void onDestroy() {

       if(mLooperThread != null){
           mLooperThread.mHandler.getLooper().quit();
       }
       super.onDestroy();
   }


```



## Looper

通过上面的例子，我们在一个线程中创建handler的时候，首先得调用Looper.prepare()方法。


```
//Looper.java

/** Initialize the current thread as a looper.
      * This gives you a chance to create handlers that then reference
      * this looper, before actually starting the loop. Be sure to call
      * {@link #loop()} after calling this method, and end it by calling
      * {@link #quit()}.
      */
    public static void prepare() {
        prepare(true);
    }

    private static void prepare(boolean quitAllowed) {
        if (sThreadLocal.get() != null) {
            throw new RuntimeException("Only one Looper may be created per thread");
        }
        sThreadLocal.set(new Looper(quitAllowed));
    }

```
除了prepare()方法，还有一个同名的带参数的方法，这个参数判断我们是否可以主动退出loop()循环，等一会我们讲到
loop()方法的时候会对这个参数有更深的理解。然后prepare方法创建了Looper对象,并将其实例保存在了sThreadLocal这个成员变量中。关于ThreadLocal我会单独写篇文章介绍，这里只要知道ThreadLocal会保存当前线程中，并且多个线程之间不会互相干扰。

Looper的构造方法：

```
private Looper(boolean quitAllowed) {
        mQueue = new MessageQueue(quitAllowed);
        mThread = Thread.currentThread();
    }

```
我们发现在Looper的构造方法中，创建了MessageQueue对象,俗称消息队列，这个是handler消息机制的另外一个主人公。我们稍后会着重对它进行介绍。总结一下Looper.prepare()所做的工作:

1. 创建Looper对象，并将其保存在ThreadLocal中
2. 在Looper中创建了MessageQueue对象

现在我们回到上面的例子，先不管Handler的创建,看Looper.loop()方法.


```

//Looper.java

/**
    * Run the message queue in this thread. Be sure to call
    * {@link #quit()} to end the loop.
    */
   public static void loop() {
       final Looper me = myLooper();
       if (me == null) {
           throw new RuntimeException("No Looper; Looper.prepare() wasn't called on this thread.");
       }
       final MessageQueue queue = me.mQueue;

       // Make sure the identity of this thread is that of the local process,
       // and keep track of what that identity token actually is.
       Binder.clearCallingIdentity();
       final long ident = Binder.clearCallingIdentity();

       for (;;) {
           Message msg = queue.next(); // 可能会阻塞在这里
           if (msg == null) {
               // No message indicates that the message queue is quitting.
               //如果没有message说明消息队列正在退出,比如调用了quit方法时
               return;
           }

           // This must be in a local variable, in case a UI event sets the logger
           final Printer logging = me.mLogging;
           if (logging != null) {
               logging.println(">>>>> Dispatching to " + msg.target + " " +
                       msg.callback + ": " + msg.what);
           }

           final long slowDispatchThresholdMs = me.mSlowDispatchThresholdMs;

           final long traceTag = me.mTraceTag;
           if (traceTag != 0 && Trace.isTagEnabled(traceTag)) {
               Trace.traceBegin(traceTag, msg.target.getTraceName(msg));
           }
           final long start = (slowDispatchThresholdMs == 0) ? 0 : SystemClock.uptimeMillis();
           final long end;
           try {
              //从消息队列中得到消息后，要将消息进行分发处理，这个target大多数就是handler
               msg.target.dispatchMessage(msg);
               end = (slowDispatchThresholdMs == 0) ? 0 : SystemClock.uptimeMillis();
           } finally {
               if (traceTag != 0) {
                   Trace.traceEnd(traceTag);
               }
           }
           if (slowDispatchThresholdMs > 0) {
               final long time = end - start;
               if (time > slowDispatchThresholdMs) {
                   Slog.w(TAG, "Dispatch took " + time + "ms on "
                           + Thread.currentThread().getName() + ", h=" +
                           msg.target + " cb=" + msg.callback + " msg=" + msg.what);
               }
           }

           if (logging != null) {
               logging.println("<<<<< Finished to " + msg.target + " " + msg.callback);
           }

           // Make sure that during the course of dispatching the
           // identity of the thread wasn't corrupted.
           final long newIdent = Binder.clearCallingIdentity();
           if (ident != newIdent) {
               Log.wtf(TAG, "Thread identity changed from 0x"
                       + Long.toHexString(ident) + " to 0x"
                       + Long.toHexString(newIdent) + " while dispatching to "
                       + msg.target.getClass().getName() + " "
                       + msg.callback + " what=" + msg.what);
           }
          //消息进行回收
           msg.recycleUnchecked();//todo，介绍消息回收的方式
       }
   }

```
代码比较长，重要的地方我做了注释，这个方法被调用后Looper就启动了，概括一下该方法做的主要工作：

1. 有个for循环，在循环中不断的从消息队列中获取消息，并且获取的方法可能会被阻塞。
2. 将获取到的Message分发出去， msg.target.dispatchMessage(msg)，这个target大多数情况就是Handler.
3. 将Message进行回收，以便可以复用，下文会详细介绍。



#### mylooper()

从ThreadLocal中获取当前线程的Looper对象

```
/**
    * Return the Looper object associated with the current thread.  Returns
    * null if the calling thread is not associated with a Looper.
    */
   public static @Nullable Looper myLooper() {
       return sThreadLocal.get();
   }

```

#### quit()和quitSafely()

退出loop循环的方法，其实他真正的实现在MessageQueue中。说一下两者的区别，quit方法是将MessageQueue中所有的消息全部清除，然后退出loop, quitSafely方法是将此时此刻，还没有到执行时间的消息清除，但是已经达到执行时间了，但是还没来得及执行的消息会保留,等执行完了再退出loop.

```
/**

   public void quit() {
       mQueue.quit(false);
   }


   public void quitSafely() {
       mQueue.quit(true);
   }

```


## MessageQueue

在上面讲Handler的时候，我们多次提到了MessageQueue，下面就介绍一下MessageQueue的原理。


#### next()

next方法的作用就是从消息队列中取出Message,当然具体不是一句话这么简单，下面看看其内部的实现。

```
//MessageQueue.java

Message next() {
        // Return here if the message loop has already quit and been disposed.
        // This can happen if the application tries to restart a looper after quit
        // which is not supported.
        final long ptr = mPtr;
        if (ptr == 0) {
            return null;
        }

        int pendingIdleHandlerCount = -1; // -1 only during first iteration
        int nextPollTimeoutMillis = 0;
        for (;;) {
            if (nextPollTimeoutMillis != 0) {
                Binder.flushPendingCommands();
            }

            nativePollOnce(ptr, nextPollTimeoutMillis);

            synchronized (this) {
                // Try to retrieve the next message.  Return if found.
                final long now = SystemClock.uptimeMillis();
                Message prevMsg = null;
                Message msg = mMessages;
                if (msg != null && msg.target == null) {
                    // Stalled by a barrier.  Find the next asynchronous message in the queue.
                    do {
                        prevMsg = msg;
                        msg = msg.next;
                    } while (msg != null && !msg.isAsynchronous());
                }
                if (msg != null) {
                    if (now < msg.when) {
                        // Next message is not ready.  Set a timeout to wake up when it is ready.
                        //如果下一条message被延时，设置一个延时，等时间到了再去返回该Message
                        nextPollTimeoutMillis = (int) Math.min(msg.when - now, Integer.MAX_VALUE);
                    } else {
                        // Got a message.
                        mBlocked = false;
                        if (prevMsg != null) {
                            prevMsg.next = msg.next;
                        } else {
                            mMessages = msg.next;
                        }
                        msg.next = null;
                        if (DEBUG) Log.v(TAG, "Returning message: " + msg);
                        msg.markInUse();
                        return msg;
                    }
                } else {
                    // No more messages.
                    nextPollTimeoutMillis = -1;
                }

                // Process the quit message now that all pending messages have been handled.
                if (mQuitting) {
                    dispose();
                    return null;
                }

                // If first time idle, then get the number of idlers to run.
                // Idle handles only run if the queue is empty or if the first message
                // in the queue (possibly a barrier) is due to be handled in the future.
                if (pendingIdleHandlerCount < 0
                        && (mMessages == null || now < mMessages.when)) {
                    pendingIdleHandlerCount = mIdleHandlers.size();
                }
                if (pendingIdleHandlerCount <= 0) {
                    // No idle handlers to run.  Loop and wait some more.
                    mBlocked = true;
                    //如果没有idle handlers需要执行，Loop将输入等待状态，也就是，next方法处于阻塞的状态，此处执行调到下一次循环，
                    //直到有新的消息，或者loop被终止，或则有idle handlers 需要执行
                    continue;
                }

                if (mPendingIdleHandlers == null) {
                    mPendingIdleHandlers = new IdleHandler[Math.max(pendingIdleHandlerCount, 4)];
                }
                mPendingIdleHandlers = mIdleHandlers.toArray(mPendingIdleHandlers);
            }

            // Run the idle handlers.
            // We only ever reach this code block during the first iteration.
            for (int i = 0; i < pendingIdleHandlerCount; i++) {
                final IdleHandler idler = mPendingIdleHandlers[i];
                mPendingIdleHandlers[i] = null; // release the reference to the handler

                boolean keep = false;
                try {
                    keep = idler.queueIdle();
                } catch (Throwable t) {
                    Log.wtf(TAG, "IdleHandler threw exception", t);
                }

                if (!keep) {
                    synchronized (this) {
                        mIdleHandlers.remove(idler);
                    }
                }
            }

            // Reset the idle handler count to 0 so we do not run them again.
            //重置idle handler的个数为0, 需要等下次再没有可执行的Message执行时，idle handler才能继续执行
            pendingIdleHandlerCount = 0;

            // While calling an idle handler, a new message could have been delivered
            // so go back and look again for a pending message without waiting.
            //需要重置这个过期时间，因为有可能有新的message需要执行，所以需要的检查
            nextPollTimeoutMillis = 0;
        }
    }


```
通过上面的代码，我们知道MessageQueue中维护了一个链表，在从队列中获取消息时，是根据消息真正的执行时间来取出的，如果这段时间空闲，也就是获取Message处于阻塞状态的时候，会回调IdleHandler,假使我们设置了它，如果当前的Message的执行时间没到，又没有IdleHandler需要处理，那么程序就会阻塞在这里。看到这里如果大家够细心的话，一定能推测出MessageQueue中的Message一定是按时间排好序的，否则Message的分发顺序就会有问题，排序的逻辑就在enqueueMessage方法中。


#### enqueueMessage

enqueueMessage方法的作用是往消息队列中添加消息，并且在插入的时候会以消息执行的时间进行排序。下面我们看看具体的代码实现，其实还是对链表的操作。


```
//MessageQueue.java

boolean enqueueMessage(Message msg, long when) {
    if (msg.target == null) {
        throw new IllegalArgumentException("Message must have a target.");
    }
    if (msg.isInUse()) {
        throw new IllegalStateException(msg + " This message is already in use.");
    }

    synchronized (this) {
        if (mQuitting) {
            IllegalStateException e = new IllegalStateException(
                    msg.target + " sending message to a Handler on a dead thread");
            Log.w(TAG, e.getMessage(), e);
            msg.recycle();//回收message todo
            return false;
        }

        msg.markInUse();
        msg.when = when;
        Message p = mMessages;
        boolean needWake;
        if (p == null || when == 0 || when < p.when) {
            // New head, wake up the event queue if blocked.
            msg.next = p;
            mMessages = msg;
            needWake = mBlocked;
        } else {
            // Inserted within the middle of the queue.  Usually we don't have to wake
            // up the event queue unless there is a barrier at the head of the queue
            // and the message is the earliest asynchronous message in the queue.
            needWake = mBlocked && p.target == null && msg.isAsynchronous();
            Message prev;
            //按时间去排序，将message插入到队列相应的位置
            for (;;) {
                prev = p;
                p = p.next;
                if (p == null || when < p.when) {
                    break;
                }
                if (needWake && p.isAsynchronous()) {
                    needWake = false;
                }
            }
            msg.next = p; // invariant: p == prev.next
            prev.next = msg;
        }

        // We can assume mPtr != 0 because mQuitting is false.
        if (needWake) {
            nativeWake(mPtr);
        }
    }
    return true;
}


```

总结一下这段代码，在往链表中插入消息时，会先对Message执行的时间进行对比，对于延时的消息,MessageQueue会遍历整个链表，直到找到合适的插入的位置。


## Message

Message顾名思义是handler消息机制中的那个消息，Handler发送和处理的实体就是这个它.

#### obtain()

当我们平时需要Message实例时，可以直接new Message(),也可以调用Message.obtain()方法，但是更推荐
使用后者，因为Message中有个Message的缓存池，这个缓存池的大小是50（从MAX_POOL_SIZE这个常量值可以得到），
而obtain()方法会先从缓存池中获取，这个缓存池也是用链表实现的。如果obtain()获取不到Message实例，才会重新new

```

public static Message obtain() {
        synchronized (sPoolSync) {
            if (sPool != null) {
              //message pool也是用链表实现的
                Message m = sPool;
                sPool = m.next;
                m.next = null;
                m.flags = 0; // clear in-use flag
                sPoolSize--;
                return m;
            }
        }
        return new Message();
    }


```

#### recycle()和recycleUnchecked()

这两个方法的作用是将使用完的Message对象进行回收，重新放入都Message缓存池中，以便下次使用，其实代码很简单，
还是对链表的操作，有没有发现链表这种数据结构真的使用的很多。

```
/**
     * Return a Message instance to the global pool.
     * <p>
     * You MUST NOT touch the Message after calling this function because it has
     * effectively been freed.  It is an error to recycle a message that is currently
     * enqueued or that is in the process of being delivered to a Handler.
     * </p>
     */
    public void recycle() {
        if (isInUse()) {
            if (gCheckRecycle) {
                throw new IllegalStateException("This message cannot be recycled because it "
                        + "is still in use.");
            }
            return;
        }
        recycleUnchecked();
    }

    /**
     * 该方法可能回收还在使用的Message
     */
    void recycleUnchecked() {
        // Mark the message as in use while it remains in the recycled object pool.
        // Clear out all other details.
        flags = FLAG_IN_USE;
        what = 0;
        arg1 = 0;
        arg2 = 0;
        obj = null;
        replyTo = null;
        sendingUid = -1;
        when = 0;
        target = null;
        callback = null;
        data = null;

        synchronized (sPoolSync) {
            if (sPoolSize < MAX_POOL_SIZE) {//Message缓存池大小为50
                next = sPool;
                sPool = this;
                sPoolSize++;
            }
        }
    }

```



## Handler

我们讲Handler消息机制，现在终于轮到Handler了，它在整个流程中就是对Message进行发送和处理。

#### Handler构造方法

```

public Handler(Callback callback, boolean async) {

      //是否检测内存泄漏的风险
      if (FIND_POTENTIAL_LEAKS) {
          final Class<? extends Handler> klass = getClass();
          if ((klass.isAnonymousClass() || klass.isMemberClass() || klass.isLocalClass()) &&
                  (klass.getModifiers() & Modifier.STATIC) == 0) {
              Log.w(TAG, "The following Handler class should be static or leaks might occur: " +
                  klass.getCanonicalName());
          }
      }

      mLooper = Looper.myLooper();//从当前的线程中获取Looper, todo
      if (mLooper == null) {//在线程中创建handle时，需要先调用Looper.prepare()
          throw new RuntimeException(
              "Can't create handler inside thread that has not called Looper.prepare()");
      }
      mQueue = mLooper.mQueue; //Looper中创建的消息队列
      mCallback = callback;//处理message的回调
      mAsynchronous = async;
  }


```


#### 发送Message

发送消息其实最终就是将根据Message的执行时间，将其插入到MessageQueue中。

```
public boolean sendMessageAtTime(Message msg, long uptimeMillis) {
    MessageQueue queue = mQueue;
    if (queue == null) {
        RuntimeException e = new RuntimeException(
                this + " sendMessageAtTime() called with no mQueue");
        Log.w("Looper", e.getMessage(), e);
        return false;
    }
    return enqueueMessage(queue, msg, uptimeMillis);
}


```



```

private boolean enqueueMessage(MessageQueue queue, Message msg, long uptimeMillis) {
       msg.target = this;
       if (mAsynchronous) {
           msg.setAsynchronous(true);
       }
       return queue.enqueueMessage(msg, uptimeMillis);
   }

```



#### 分发消息

Looper在调用loop()方法的时候，当遇到符合条件的Message，就会调用Handler的dispatchMessage方法，
用来分发Message，这样我们就可以在Handler中处理Message了。

```

/**
   * Handle system messages here.
   */
  public void dispatchMessage(Message msg) {
      if (msg.callback != null) {
          handleCallback(msg);
      } else {
          if (mCallback != null) {
              if (mCallback.handleMessage(msg)) {
                  return;
              }
          }
          handleMessage(msg);
      }
  }

```

## IdleHandler

前面在讲MessageQueue的next的方法的时候见到过IdleHandler，当我们取消息处于阻塞状态的时候，如果添加了IdleHandler，就会处理它，所以我们可以把一些不那么重要的操作放到IdleHandler中执行，这样可以显著的提高性能。比如著名的内存泄漏检测库[leakarary](https://github.com/square/leakcanary)中关于内存泄漏检测的操作就放到了IdleHandler中执行。


```

/**
    * Callback interface for discovering when a thread is going to block
    * waiting for more messages.
    */
   public static interface IdleHandler {

      /**
        * 在该方法中执行我们需要执行的任务，如果该任务是一次性的则返回false,如果该任务需要多次
        * 执行则返回true
        */
       boolean queueIdle();
   }


```



## 总结


到这里Java层的Handler机制就讲完了，限于篇幅的原因和作者的水平，有些地方没有很深入的讲解，在此说声抱歉，但是大致的流程应该是有的，建议读者去仔细的读一下这块的源码，相信收获会不小。








