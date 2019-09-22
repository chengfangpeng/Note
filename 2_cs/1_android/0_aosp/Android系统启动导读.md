
## Android启动中涉及到的重要进程

#### init进程

Linux系统用户空间中的第一个进程,init拉起zygote进程
1. 创建一块共享内存空间，用于属性服务器
2. 解析各个rc文件，并启动相应的服务进程
3. 进入无线循环状态


#### zygote进程

所有app进程的父进程。

在App_main.main方法中如果zygote为false,执行执行AndroidRuntime.main方法，该方法又会调用AndroidRuntime::start方法，它的主要作用是:

1. 创建虚拟机
2. JNI注册
3. 跳转到ZygoteInit.main方法

回到上面的节点，如果zygote为true，就直接调用ZygoteInit.main方法，这个方法的功能：

1. 为Zygote注册socket
2. 预加载类和资源
3. 启动system_server进程
4. 循环，当需要创建新进程时立即唤醒，并执行相应的工作。






#### servicemanager进程

binder服务的大管家


#### system_server进程

系统各大服务的载体,SystemServer.main方法被调用执行，然后调用SystemServer.run方法，在run
方法中做的工作:

1. 准备主线程的looper(ActivityThread中类似的过程的区别)
2. 创建和启动各种系统服务
3. Looper.loop()


#### ActivityManagerService

1. 杀掉所有非persistent的进程
2. 启动所有persistent的进程
3. 启动home(home是什么，是launcher吗)



## 创建app进程

app进程通过Zygote创建后，会调用ActivityThread.main方法,在main方法中会启动Looper.loop()




## 通过adb shell am 命令启动进程

通过这种方式启动进程会调用到RuntimeInit.main中，fork创建进程的方式，采用的是linux copy on write的方式
会有两次返回，如果pid=0是子进程的返回，如果pid>0，是父进程的返回，当出错时，返回-1
