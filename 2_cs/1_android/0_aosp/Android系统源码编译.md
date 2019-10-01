## 前言
为什么要编译Android的系统源码:
1. 为了更彻底的学习Android系统的底层原理
2. 工作的需要，开发一个冰箱的带屏系统

## 环境要求
|参数|值|
|--|--|
| 系统| Ubuntu16.04|
|硬盘|250G(越多越好)|
|内存|16G(越大越好)|
|cpu核数|8核|
|编译的Android版本|6.0|
|java版本|openjdk7|

## 安装Jdk

如果使用的OpenJDK7，由于Ubuntu 16.04没有OpenJDK7的源，因此要先添加源，然后在安装OpenJDK7，按下面的命令操作即可：
```
sudo add-apt-repository ppa:openjdk-r/ppa
sudo apt-get update
sudo apt-get install openjdk-7-jdk

```
> 注意如果编译的是Android6.0只能使用openjdk7，具体的版本可以参考这里

## 安装依赖

```
sudo apt-get install -y git flex bison gperf build-essential libncurses5-dev:i386
sudo apt-get install libx11-dev:i386 libreadline6-dev:i386 libgl1-mesa-dev g++-multilib
sudo apt-get install tofrodos python-markdown libxml2-utils xsltproc zlib1g-dev:i386
sudo apt-get install dpkg-dev libsdl1.2-dev libesd0-dev
sudo apt-get install git-core gnupg flex bison gperf build-essential  
sudo apt-get install zip curl zlib1g-dev gcc-multilib g++-multilib
sudo apt-get install libc6-dev-i386
sudo apt-get install lib32ncurses5-dev x11proto-core-dev libx11-dev
sudo apt-get install lib32z-dev ccache
sudo apt-get install libgl1-mesa-dev libxml2-utils xsltproc unzip m4
```



## 下载源码

Android的源码是使用我们熟悉的Git和Repo两种代码管理工具共同管理的，Git不用介绍了，大家都很熟悉，说说Repo,它是用python开发的一个整合Git仓库的工具，在管理Android源码时，使用Repo往往会简化我们代码管理的工作。

#### 下载repo工具

- Google源(需要能科学上网)

```
mkdir ~/bin
PATH=~/bin:$PATH
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo
```

如果不能翻墙的同学可以使用清华大学的镜像

- 清华源

```
curl https://mirrors.tuna.tsinghua.edu.cn/git/git-repo -o ~/bin/repo
chmod +x ~.bin/repo

```

有时候repo也需要更新，为了使用清华源更新需要将源地址配置到环境变量中。

```
export REPO_URL='https://mirrors.tuna.tsinghua.edu.cn/git/git-repo/'

```

将上面的内容配置到~/.bashrc文件中，source ~/.bashrc 环境变量就生效了。

#### 初始化仓库

```
mkdir ~/aosp
cd aosp
```

```
repo init -u https://aosp.tuna.tsinghua.edu.cn/platform/manifest -b android-6.0.1_r79
```

如果想初始化某个特定的android版本可以参考这个[列表](https://source.android.com/setup/start/build-numbers#source-code-tags-and-builds), 但是要注意jdk的版本，要不一会可能编不过。

#### 同步代码

```
repo sync
```

这个时候，代码就开始下载了，一般情况下需要几个小时，如果中间出错重复上面的命令就可以了。



## 编译源码



#### 设置环境

```
source build/envsetup.sh
```

envsetup.sh 脚本中导入了一些很有用的命令，我们可以通过下面的命令查看envsetup中提供的全部命令工具

```
hmm
```

```
- lunch:   lunch <product_name>-<build_variant>
- tapas:   tapas [<App1> <App2> ...] [arm|x86|mips|armv5|arm64|x86_64|mips64] [eng|userdebug|user]
- croot:   Changes directory to the top of the tree.
- m:       Makes from the top of the tree.
- mm:      Builds all of the modules in the current directory, but not their dependencies.
- mmm:     Builds all of the modules in the supplied directories, but not their dependencies.
           To limit the modules being built use the syntax: mmm dir/:target1,target2.
- mma:     Builds all of the modules in the current directory, and their dependencies.
- mmma:    Builds all of the modules in the supplied directories, and their dependencies.
- cgrep:   Greps on all local C/C++ files.
- ggrep:   Greps on all local Gradle files.
- jgrep:   Greps on all local Java files.
- resgrep: Greps on all local res/*.xml files.
- mangrep: Greps on all local AndroidManifest.xml files.
- sepgrep: Greps on all local sepolicy files.
- sgrep:   Greps on all local source files.
- godir:   Go to the directory containing a file.

```

下面简单的介绍一下这几个命令：

- lunch 

  选择编译的类型，直接执行lunch命令，就会列出要编译的类型。编译类型分为下面的类型

  | 编译类型  | 使用情况                                                     |
  | --------- | ------------------------------------------------------------ |
  | user      | 权限受限,不能调试，没有root；适用于生产环境                  |
  | userdebug | 与“user”类似，但具有 root 权限和调试功能；是进行调试时的首选编译类型 |
  | eng       | 具有额外调试工具的开发配置                                   |

- m

  同make, 编译所有的模块

- mm

  编译单独的模块，需要切换到模块所在的目录

- mmm

  编译单独的模块，不需要切换到模块所在的目录

- croot

  回到源码的根目录

#### 开始编译

```
make -j 8
```

-j 参数可以设置并发任务的数量，这个值一般和系统的核心数有关

经过两个多小时的编译，就可以看到编译成功的提示了。



#### 启动模拟器，运行我们编译出来的系统镜像。

```
emulator
```

这样就看到我们编译出来的效果了。

## 单独编译模块

有时候我们修改源码的时候，可能只改了某一个模块，是否需要将整个系统编译一遍呢，google怎么可能会做这种蠢事，答案当然是肯定的。

例如我们想重新编译Setting应用，只需要执行下面的命令

```
mmm /packages/apps/Setting
```

之后，重新打包一下system.img文件

```
make snod
```

这个命令的作用是快速的构建一个镜像文件，但是,不是所有的情况都使用，它不会检查依赖，如果我们修改了framework层的代码，这种方式就不适用了，因为它有可能会影响到其他的app而不只是Setting.



## 制作ota升级包



## 卡刷和线刷



## 代码实现OTA升级





## 资料

- 

## 错误解决

- 错误1

  ```
  build/core/host_shared_library_internal.mk:51: recipe for target 'out/host/linux-x86/obj/lib/libart.so' failed
  ```

  解决方法：

  ```
  在 art/build/Android.common_build.mk 中，找到WITHOUT_HOST_CLANG，将clang关闭
  
  # Host.
  ART_HOST_CLANG := false
  ifneq ($(WITHOUT_HOST_CLANG),true)
    # By default, host builds use clang for better warnings.
    ART_HOST_CLANG := false
  
  ```

  







