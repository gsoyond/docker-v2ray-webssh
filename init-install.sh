#!/bin/bash

cd "$(
    cd "$(dirname "$0")" || exit
    pwd
)" || exit

#fonts color
Green="\033[32m"
Red="\033[31m"
# Yellow="\033[33m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
Font="\033[0m"

#notification information
# Info="${Green}[信息]${Font}"
OK="${Green}[OK]${Font}"
Error="${Red}[错误]${Font}"


#配置信息
base_dir=$(cd "$(dirname "$0")";pwd)
data_dir="$base_dir/data"
log_dir="$base_dir/logs"
nginx_base_dir="$data_dir/nginx"
nginx_www_dir="$nginx_base_dir/html"
acme_cert_dir="$data_dir/acme/cert"
acme_www_dir="$data_dir/acme/www"
nginx_config_dir="$nginx_base_dir/conf.d"
nginx_v2ray_config_file="$nginx_config_dir/v2ray.conf"
nginx_webssh_config_file="$nginx_config_dir/webssh.conf"
nginx_webssh_basic_auth_file="$nginx_config_dir/passwd"
nginx_log_dir="$log_dir/nignx"
v2ray_base_dir="$data_dir/v2ray"
v2ray_config_dir="$v2ray_base_dir"
v2ray_config_file="$v2ray_config_dir/config.json"
v2ray_log_dir="$log_dir/v2ray"

v2ray_qr_config_file="$v2ray_config_dir/qr_info.json"

install_info_file="$data_dir/info.txt"

docker_compose_file="$base_dir/docker-compose.yml"

judge() {
    if [[ 0 -eq $? ]]; then
        echo -e "${OK} ${GreenBG} $1 完成 ${Font}"
        sleep 1
    else
        echo -e "${Error} ${RedBG} $1 失败${Font}"
        exit 1
    fi
}

check_system() {

	if sudo -v &>/dev/null;
	then  
		SUDO="sudo"
	else 
		if ! [ $(id -u) = 0 ]; then
		   echo "请以root用户或具有sudo权限的用户运行脚本"
		   exit 1
		else
			SUDO=""
		fi
	fi

	source '/etc/os-release'
	VERSION=$(echo "${VERSION}" | awk -F "[()]" '{print $2}')

    if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Centos ${VERSION_ID} ${VERSION} ${Font}"
        INS="${SUDO} yum"
    elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 8 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Debian ${VERSION_ID} ${VERSION} ${Font}"
        INS="${SUDO} apt"        
        ## 添加 Nginx apt源
    elif [[ "${ID}" == "ubuntu" && $(echo "${VERSION_ID}" | cut -d '.' -f1) -ge 16 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Ubuntu ${VERSION_ID} ${UBUNTU_CODENAME} ${Font}"
        INS="${SUDO} apt"        
    else
        echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内，安装中断 ${Font}"
        exit 1
    fi
	
	${INS} update

    ${SUDO} systemctl stop firewalld
    ${SUDO} systemctl disable firewalld
    echo -e "${OK} ${GreenBG} firewalld 已关闭 ${Font}"

    ${SUDO} systemctl stop ufw
    ${SUDO} systemctl disable ufw
    echo -e "${OK} ${GreenBG} ufw 已关闭 ${Font}"
}

install_bbr() {
	has_su_root=0
	if ! [[ $(id -u) = 0 ]]; then
	   echo "BBR 加速脚本需要以root用户运行。现在切换到root用户..."
	   su -l root
	   has_su_root=1
	fi
	
	[[ -f "bbr.sh" ]] && rm -f ./bbr.sh
    wget -N --no-check-certificate -O bbr.sh "https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh" && chmod +x bbr.sh && ./bbr.sh

	if [[ 1 -eq ${has_su_root} && $(id -u) = 0 ]]; then
        $(logout)
		echo "已退出root用户登录."
    fi
}

init_env(){
	#安装必要的环境，包括docker、docker-compose	
	echo -e "${OK} ${GreenBG} 安装必要的环境，包括docker、docker-compose、amce.sh、qrencode ${Font}"
	
	if [[ -x "$(command -v docker)" ]]; then
		echo -e "${OK} ${GreenBG} docker已存在。 ${Font}"
	else
		curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh

		#如果是非root用户，需要加入docker组，才能操作docker
		if ! [[ $(id -u) = 0 ]]; then
			cur_user=$USER
			${SUDO} gpasswd -a ${cur_user} docker
			#需要退出重新登录后才能生效
			$(logout)
			$(su - l "${cur_user}")
		fi
		judge "安装docker"	
	fi	
	
	${SUDO} systemctl start docker
	${SUDO} systemctl enable docker
	
	if [[ -x "$(command -v docker-compose)" ]]; then
		echo -e "${OK} ${GreenBG} docker-compose已存在。 ${Font}"
	else
		${SUDO} curl -L "https://github.com/docker/compose/releases/download/1.25.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose \
			&& ${SUDO} chmod +x /usr/local/bin/docker-compose \
			&& ${SUDO} ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
		judge "安装docker-compose"
	fi

	if [[ -x "$(command -v $HOME/.acme.sh/acme.sh)" ]]; then
		echo -e "${OK} ${GreenBG} acme.sh已存在。 ${Font}"
	else	
		curl https://get.acme.sh | sh
		judge "安装acme.sh"
	fi

	${INS} -y install qrencode
    judge "安装 qrencode"
	
	#建立必要的路径 
	[[ ! -d ${nginx_www_dir} ]] && mkdir -p ${nginx_www_dir}
	[[ ! -d ${nginx_config_dir} ]] && mkdir -p ${nginx_config_dir}
	[[ ! -d ${v2ray_config_dir} ]] && mkdir -p ${v2ray_config_dir}
	[[ ! -d ${nginx_log_dir} ]] && mkdir -p ${nginx_log_dir}
	[[ ! -d ${v2ray_log_dir} ]] && mkdir -p ${v2ray_log_dir}

	[[ ! -d "${acme_www_dir}/.well-known/acme-challenge" ]] && mkdir -p "${acme_www_dir}.well-known/acme-challenge"
	[[ ! -d ${acme_cert_dir} ]] && mkdir -p ${acme_cert_dir}
	
}

acme(){
	echo -e "${GreenBG} 开始申请域名认证证书 ${Font}"
	if  [[ ! -n "$1" ]] ;then
		read -arp "请输入域名，多个域名请用空格风格:" domains
	else
		domains=( "$1" )
	fi
	
	domain_args=""
	for domain in "${domains[@]}"; do
	  domain_args="$domain_args -d $domain"
	done
	main_domain="${domains[0]}"

	if [[ -d "${acme_cert_dir}/${main_domain}" ]]; then
	  read -p "$domains 的证书已存在，是否确认申请并覆盖？(y/N) " decision
	  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
		exit
	  fi
	fi
	
	echo -e "${GreenBG} 开始域名认证，${domains} ${Font}"
	#启动nginx容器
	echo "### Starting nginx ..."
	docker-compose up --force-recreate -d nginx	
		
	"$HOME"/.acme.sh/acme.sh --issue ${domain_args} -w ${acme_www_dir} -k ec-256 --force 
	judge "域名证书申请"
			
	echo -e "${GreenBG} 开始安装证书 ${Font}"
	"$HOME"/.acme.sh/acme.sh --install-cert ${domain_args} \
		--key-file       ${acme_cert_dir}/${main_domain}/key.pem  \
		--fullchain-file ${acme_cert_dir}/${main_domain}/fullchain.pem \
		--reloadcmd     "docker exec nginx nginx -s reload"
	judge "域名证书安装"
	echo -e "${OK} ${GreenBG} 证书安装路径为${nginx_cert_dir}/${main_domain} ${Font}" 
}

start_server(){
	cd ${base_dir}
	
	if ! [ -x "$(command -v docker-compose)" ]; then
	  echo 'Error: docker-compose is not installed.' >&2
	  exit 1
	fi
	
	docker-compose up
}

vmess_qr_config_tls_ws() {
    cat >${v2ray_qr_config_file} <<-EOF
{
  "v": "2",
  "ps": "glx_${domain_v2ray}",
  "add": "${domain_v2ray}",
  "port": "443",
  "id": "${UUID}",
  "aid": "${alterID}",
  "net": "ws",
  "type": "none",
  "host": "${domain_v2ray}",
  "path": "/${camouflage}/",
  "tls": "tls"
}
EOF

}

vmess_qr_link_image() {
    vmess_link="vmess://$(base64 -w 0 $v2ray_qr_config_file)"
    {
        echo -e "$Red V2ray二维码: $Font"
        echo -n "${vmess_link}" | qrencode -o - -t utf8
        echo -e "${Red} URL导入链接: ${vmess_link} ${Font}"
    } >>"${install_info_file}"
}

info_extraction() {
    grep "$1" ${v2ray_qr_config_file} | awk -F '"' '{print $4}'
}

basic_information() {
    {
        echo -e "${OK} ${GreenBG} V2ray+ws+tls 安装成功"
        echo -e "${Red} V2ray 配置信息 ${Font}"
        echo -e "${Red} 地址（address）:${Font} $(info_extraction '\"add\"') "
        echo -e "${Red} 端口（port）：${Font} $(info_extraction '\"port\"') "
        echo -e "${Red} 用户id（UUID）：${Font} $(info_extraction '\"id\"')"
        echo -e "${Red} 额外id（alterId）：${Font} $(info_extraction '\"aid\"')"
        echo -e "${Red} 加密方式（security）：${Font} 自适应 "
        echo -e "${Red} 传输协议（network）：${Font} $(info_extraction '\"net\"') "
        echo -e "${Red} 伪装类型（type）：${Font} none "
        echo -e "${Red} 路径（不要落下/）：${Font} $(info_extraction '\"path\"') "
        echo -e "${Red} 底层传输安全：${Font} tls "
		echo -e "${OK} ${GreenBG} webssh 安装成功"
		echo -e "${Red} webssh 配置信息 ${Font}"
        echo -e "${Red} 地址（address）:${Font} $domain_webssh "
		echo -e "${Red} Basic认证用户名（username）:${Font} $webssh_auth_username "
		echo -e "${Red} Basic认证密码（username）:${Font} $webssh_auth_password "
        echo -e "${Red} 传输协议（network）：${Font} TLS加密传输 "
    } >"${install_info_file}"
}

show_information() {
    cat "${install_info_file}"
}

install(){
	echo
	echo -e "${OK} ${GreenBG} 本脚本将使用docker-compose安装nginx、v2ray和webssh，完成tls+ws的配置。 ${Font}"
	echo -e "${OK} ${GreenBG} 请准备好2个域名，一个给v2ray，一个给ssh。 ${Font}"
	echo -e "${OK} ${GreenBG} 先输入v2ray的配置信息： ${Font}"
	read -rp "请输入用于v2ray的域名信息:" domain_v2ray
	read -rp "请输入websocket伪装路径（default:ws）:" camouflage
    [[ -z ${camouflage} ]] && camouflage="ws"
	read -rp "请输入alterID（default:64 仅允许填数字）:" alterID
    [[ -z ${alterID} ]] && alterID="64"
	echo -e "${OK} ${GreenBG} 自动生成随机UUID ${Font}"
	[ -z "$UUID" ] && UUID=$(cat /proc/sys/kernel/random/uuid)
	echo -e "${OK} ${GreenBG} UUID:${UUID} ${Font}"
	
	echo -e "${OK} ${GreenBG} 再输入webssh的配置信息： ${Font}"
	read -rp "请输入用于webssh的域名信息:" domain_webssh
	read -rp "为加强webssh站点安全，采用Basic认证。请设置用户名:" webssh_auth_username
	read -rp "请设置密码(最长8个字符):" webssh_auth_password
	
	printf "${webssh_auth_username}:$(openssl passwd -crypt ${webssh_auth_password})\n" >> ${nginx_webssh_basic_auth_file}
	echo
	
	echo -e "${GreenBG} 修改nginx和v2ray配置信息 ${Font}"
	sed -i "s/your_domain/${domain_v2ray}/g" ${nginx_v2ray_config_file}	
	sed -i "s/your_domain/${domain_webssh}/g" ${nginx_webssh_config_file}
	sed -i "s/your_ws_path/${camouflage}/g" ${nginx_v2ray_config_file}
	
	sed -i "s/your_ws_path/${camouflage}/g" ${v2ray_config_file}
	sed -i "s/your_uuid/${UUID}/g" ${v2ray_config_file}
	sed -i "s/your_alterId/${alterID}/g" ${v2ray_config_file}
	
	
	echo -e "${GreenBG} 开始认证v2ray的域名 ${domain_v2ray} ${Font}"
	acme ${domain_v2ray}
	echo -e "${GreenBG} 开始认证wenssh的域名 ${domain_webssh} ${Font}"
	acme ${domain_webssh}
	echo
	
	echo -e "${GreenBG} 开始启动服务 ${Font}"
	start_server
	judge "服务启动"
	
	## 配置信息写入
	vmess_qr_config_tls_ws
	basic_information
}

menu() {
   
    echo -e "\t V2ray and Webssh 安装脚本"
    echo -e "\t---authored by glx---"
	echo -e "\t V2ray采用nginx+tls+ws，webssh前置nginx代理，完成https接入。BBR加速使用chiakge的脚本"

    echo -e "—————————————— 安装向导 ——————————————"""
    echo -e "${Green}0.${Font}  安装 BBR 加速"
    echo -e "${Green}1.${Font}  安装 V2Ray + Webssh "
    echo -e "—————————————— 证书安装 ——————————————"
	echo -e "${Green}2.${Font}  证书 为域名安装证书"
    echo -e "—————————————— 查看信息 ——————————————"
    echo -e "${Green}3.${Font}  查看 配置信息"
    echo -e "${Green}4.${Font}  退出 \n"

    read -rp "请输入数字：" menu_num
    case $menu_num in
    0)
        install_bbr
        ;;
    1)
		check_system
		init_env
        install
        ;;
    2)
        acme
        ;;
    3)        
        show_information
        ;;
    4)
        exit 0
        ;;
    *)
        echo -e "${RedBG}请输入正确的数字${Font}"
        ;;
    esac
}

menu

