#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}mistake：${plain} Webilo: This script must be run with the root user！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}System version not detected, please contact the script author！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="amd64"
    echo -e "${red}Failed to detect schema, use default schema: ${arch}${plain}"
fi

echo "architecture: ${arch}"

if [ $(getconf WORD_BIT) != '32' ] && [ $(getconf LONG_BIT) != '64' ]; then
    echo "This software does not support 32-bit system (x86), please use 64-bit system (x86_64), if the detection is wrong, please contact the author"
    exit -1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Please use CentOS 7 or later system！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Please use Ubuntu 16 or later system！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Please use Debian 8 or higher！${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl tar -y
    else
        apt install wget curl tar -y
    fi
}

#This function will be called when user installed x-ui out of sercurity
config_after_install() {

    yellow "For security reasons, after the installation/ update, you need to remember the port and the account password"
    read -rp "Please set the login user name [default is a random user name]: " config_account
    [[ -z $config_account ]] && config_account=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "Please set the login password. Don't include spaces [default is a random password]: " config_password
    [[ -z $config_password ]] && config_password=$(date +%s%N | md5sum | cut -c 1-8)
    read -rp "Please set the panel access port [default is a random port]: " config_port
    [[ -z $config_port ]] && config_port=$(shuf -i 1000-65535 -n 1)
    until [[ -z $(ss -ntlp | awk '{print $4}' | grep -w "$config_port") ]]; do
        if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w  "$config_port") ]]; then
            yellow "The port you set is currently in uese, please reassign another port"
            read -rp "Please set the panel access port [default ia a random port]: " config_port
            [[ -z $config_port ]] && config_port=$(shuf -i 1000-65535 -n 1)
        fi
    done
    /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password} >/dev/null 2>&1
    /usr/local/x-ui/x-ui setting -port ${config_port} >/dev/null 2>&1
}
}

install_x-ui() {
    systemctl stop x-ui
    cd /usr/local/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/vaxilu/x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Webilo: Failed to detect the x-ui version, it may be beyond the limit of Github API, please try again later, or manually specify the x-ui version to install${plain}"
            exit 1
        fi
        echo -e "Detected the latest version of x-ui：${last_version}，start installation"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz https://github.com/vaxilu/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download x-ui failed, please make sure your server can download files from Github${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/vaxilu/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
        echo -e "start installation x-ui v$1"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Download x-ui v$1 failed, please make sure this version exists${plain}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux-${arch}.tar.gz
    rm x-ui-linux-${arch}.tar.gz -f
    cd x-ui
    chmod +x x-ui bin/xray-linux-${arch}
    cp -f x-ui.service /etc/systemd/system/
    wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/vaxilu/x-ui/main/x-ui.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    config_after_install
    #echo -e "If it is a new installation, the default web port is ${green}54321${plain}, and the default username and password are ${green}admin${plain}"
     #echo -e "Please ensure that this port is not occupied by other programs, ${yellow} and ensure that port 54321 has been released ${plain}"
     # echo -e "If you want to modify 54321 to another port, enter the x-ui command to modify, and also make sure that the port you modified is also allowed"
     #echo -e ""
     #echo -e "If updating the panel, access the panel as you did before"
     #echo -e ""
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
      echo -e ""
    echo -e "${GREEN} --------------------------------------------------------------------  ${PLAIN}"
    echo -e "${GREEN}                                                                                                  ${PLAIN}"
 echo -e "${GREEN}─────────────────────────────────────────────────────────────────────────────────────────────────       ${PLAIN}"
 echo -e "${GREEN}─██████──────────██████─██████████████─██████████████───██████████─██████─────────██████████████─    ${PLAIN}"
 echo -e "${GREEN}─██░░██──────────██░░██─██░░░░░░░░░░██─██░░░░░░░░░░██───██░░░░░░██─██░░██─────────██░░░░░░░░░░██─          ${PLAIN}"
 echo -e "${GREEN}─██░░██──────────██░░██─██░░██████████─██░░██████░░██───████░░████─██░░██─────────██░░██████░░██─          ${PLAIN}"
 echo -e "${GREEN}─██░░██──────────██░░██─██░░██─────────██░░██──██░░██─────██░░██───██░░██─────────██░░██──██░░██─           ${PLAIN}"
 echo -e "${GREEN}─██░░██──██████──██░░██─██░░██████████─██░░██████░░████───██░░██───██░░██─────────██░░██──██░░██─        ${PLAIN}"
 echo -e "${GREEN}─██░░██──██░░██──██░░██─██░░░░░░░░░░██─██░░░░░░░░░░░░██───██░░██───██░░██─────────██░░██──██░░██─          ${PLAIN}"
 echo -e "${GREEN}─██░░██──██░░██──██░░██─██░░██████████─██░░████████░░██───██░░██───██░░██─────────██░░██──██░░██─          ${PLAIN}"
 echo -e "${GREEN}─██░░██████░░██████░░██─██░░██─────────██░░██────██░░██───██░░██───██░░██─────────██░░██──██░░██─           ${PLAIN}"
 echo -e "${GREEN}─██░░░░░░░░░░░░░░░░░░██─██░░██████████─██░░████████░░██─████░░████─██░░██████████─██░░██████░░██─             ${PLAIN}"
 echo -e "${GREEN}─██░░██████░░██████░░██─██░░░░░░░░░░██─██░░░░░░░░░░░░██─██░░░░░░██─██░░░░░░░░░░██─██░░░░░░░░░░██─             ${PLAIN}"
 echo -e "${GREEN}─██████──██████──██████─██████████████─████████████████─██████████─██████████████─██████████████─                ${PLAIN}"
    echo -e "${GREEN} --------------------------------------------------------------------- ${PLAIN}"
    echo -e ""
    echo -e "X-UI MANAGEMENT SCRIPT USAGE: "
    echo -e "------------------------------------------------------------------------------"
    echo -e "x-ui              - Show the management menu"
    echo -e "x-ui start        - Start X-UI panel"
    echo -e "x-ui stop         - Stop X-UI panel"
    echo -e "x-ui restart      - Restart X-UI panel"
    echo -e "x-ui status       - View X-UI status"
    echo -e "x-ui enable       - Set X-UI boot self-starting"
    echo -e "x-ui disable      - Cancel X-UI boot self-starting"
    echo -e "x-ui log          - View x-ui log"
    echo -e "x-ui v2-ui        - Migrate V2-UI to X-UI"
    echo -e "x-ui update       - Update X-UI panel"
    echo -e "x-ui install      - Install X-UI panel"
    echo -e "x-ui uninstall    - Uninstall X-UI panel"
    echo -e "------------------------------------------------------------------------------"
    echo -e "------------------------------------------------------------------------------"
    echo -e "Please do consider supporting authors"
    echo -e "------------------------------------------------------------------------------"
    echo -e "                           █░█░█ █▀▀ █▄▄ █ █░░ █▀█
                                        ▀▄▀▄▀ ██▄ █▄█ █ █▄▄ █▄█                           "
    echo -e "--------------------------------------------------------------------------------"
    show_login_info
    yellow "(If you cannot access the X-UI panel, first enter the X-UI command in the SSH command line, and then select the 17 option to let go of the firewall port)"


show_login_info(){
    if [[ -n $v4 && -z $v6 ]]; then
        echo -e "Panel IPv4 login address is: ${GREEN}http://$v4:$config_port ${PLAIN}"
    elif [[ -n $v6 && -z $v4 ]]; then
        echo -e "Panel IPv6 login address is: ${GREEN}http://[$v6]:$config_port ${PLAIN}"
    elif [[ -n $v4 && -n $v6 ]]; then
        echo -e "Panel IPv4 login address is: ${GREEN}http://$v4:$config_port ${PLAIN}"
        echo -e "Panel IPv6 login address is: ${GREEN}http://[$v6]:$config_port ${PLAIN}"
    fi
    echo -e "Username: ${GREEN}$config_account ${PLAIN}"
    echo -e "Password: ${GREEN}$config_password ${PLAIN}"
}


