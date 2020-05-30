# docker-v2ray-webssh

使用docker-compose一键部署v2ray(nginx+tls+ws)+webssh。

## 如何使用

1、开始之前，需要准备两个域名，一个给v2ray用，一个给webssh用。

2、使用root用户登录vps，并新建具有sudo权限的新用户`v2ray`。为安全起见，建议新建单独的用户，而不用root用户执行本脚本。
```
adduser v2ray
passwd v2ray
gpasswd -a v2ray wheel
su -l v2ray
```

3、安装git，并clone本repo。
```
sudo yum -y intall git

git clone https://github.com/gsoyond/docker-v2ray-webssh.git
```

4、进入`docker-v2ray-webssh`目录，添加执行权限，并运行`init-install.sh`。
```
cd docker-v2ray-webssh
chmod +x init-install.sh
./init-install.sh
```

5、根据提示完成安装。

6、安装完成后会输出v2ray的配置信息，并打印二维码，手机客户端可以直接扫描完成配置，pc客户端可以直接复制vmess连接。

### 参考

1、[aitlp/docker-v2ray](https://github.com/aitlp/docker-v2ray)

2、[wulabing/V2Ray_ws-tls_bash_onekey](https://github.com/wulabing/V2Ray_ws-tls_bash_onekey)

3、[chiakge/Linux-NetSpeed](https://github.com/chiakge/Linux-NetSpeed)
