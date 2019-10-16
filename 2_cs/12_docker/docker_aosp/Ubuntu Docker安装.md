
## 18.04版本安装Docker


```
sudo apt-get update
```

```
sudo apt-get install \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common

```

```
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
```

```
sudo apt-key fingerprint 0EBFCD88
```

```
sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

```

```
sudo apt-get update

```

```
sudo apt-get install docker-ce docker-ce-cli containerd.io

```

## 修改docker配置文件

1. 替换ｉd_rsa和ｉd_rsa.pub为自己主机的ssh

2. ssh_config 中用户改为自己的用户名

3. 配置源码存放的位置,路径替换为自己的路径,修改方式为，打开docker_aosp文件，替换下面的路径

```
AOSP_VOL=${AOSP_VOL:-/media/cfp/Data/aosp_docker}
```




## 创建编译TVOS的镜像

```
 sudo docker image build -t docker_aosp .

```

## 启动docker容器

```
sudo ./docker_aosp
```

## 开始下载源码编译

进入到/home/aosp　目录

```
./build_tv_920.sh
```
