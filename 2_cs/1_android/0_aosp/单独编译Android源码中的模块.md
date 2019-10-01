## 执行envsetup.sh

在build目录下有个**envsetup.sh**脚本，执行这个脚本之后可以获取很多有用的工具。如下是它提供的命令工具

```bash
- lunch:     lunch <product_name>-<build_variant>
- tapas:     tapas [<App1> <App2> ...] [arm|x86|mips|armv5|arm64|x86_64|mips64] [eng|userdebug|user]
- croot:     Changes directory to the top of the tree.
- m:         Makes from the top of the tree.
- mm:        Builds all of the modules in the current directory, but not their dependencies.
- mmm:       Builds all of the modules in the supplied directories, but not their dependencies.
             To limit the modules being built use the syntax: mmm dir/:target1,target2.
- mma:       Builds all of the modules in the current directory, and their dependencies.
- mmma:      Builds all of the modules in the supplied directories, and their dependencies.
- provision: Flash device with all required partitions. Options will be passed on to fastboot.
- cgrep:     Greps on all local C/C++ files.
- ggrep:     Greps on all local Gradle files.
- jgrep:     Greps on all local Java files.
- resgrep:   Greps on all local res/*.xml files.
- mangrep:   Greps on all local AndroidManifest.xml files.
- mgrep:     Greps on all local Makefiles files.
- sepgrep:   Greps on all local sepolicy files.
- sgrep:     Greps on all local source files.
- godir:     Go to the directory containing a file.
```



## 使用mmm执行指定的模块

例如，我们想单独编译launcher,那么久可以执行下面的命令：

```bash
mmm /packages/apps/Setting
```

## 重新打包一下system.img文件

```bash
make snod
```

这个命令的作用是快速的构建一个镜像文件，但是,不是所有的情况都使用，它不会检查依赖，如果我们修改了framework层的代码，这种方式就不适用了，因为它有可能会影响到其他的app而不只是Setting.



