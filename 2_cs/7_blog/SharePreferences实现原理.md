## SP提纲

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


## 前言

SharedPreferences可能是我们用的最多的Android键值对存储工具了。但是它对我们来说熟悉而又陌生，熟悉是因为它使用足够简单，陌生是因为它有所谓的“七宗罪”在性能和多进程方面有定的问题。下面我会结合源码把我们在使用中遇到的各种问题一一的解开
