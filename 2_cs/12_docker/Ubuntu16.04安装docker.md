

## 把当前用户添加到docker组

```
sudo usermod -aG docker $USER
```

## 启动docker服务

```
# service 命令的用法
$ sudo service docker start
```

## 修改image 仓库的镜像网址

打开/etc/default/docker文件（需要sudo权限），在文件的底部加上一行。

```
DOCKER_OPTS="--registry-mirror=https://registry.docker-cn.com"
```
然后重启服务

```
sudo service docker restart
```


## docker容器启动终端

```
sudo docker ps -a
sudo docker exec -it 9df70f9a0714 /bin/bash

```


## 灵感
可以用火锅中的鸳鸯锅做比喻
