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


> 细推物理须行乐,何用浮名绊此身

## 前言
SharedPreferences是Android轻量级的键值对存储方式。对于开发者来说它的使用非常的方便，但是也是一种被大家诟病很多的一种存储方式。下面我会提出一些平时在使用SharedPreferences中遇到的问题，然后通过SharedPreferences的源码，一步步的拨云见日。

## SharedPreferences问题总结
