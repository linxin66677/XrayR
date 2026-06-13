#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

REPO_RAW="https://raw.githubusercontent.com/linxin66677/XrayR/master"
INSTALL_DIR="/usr/local/XrayR"
CONFIG_DIR="/etc/XrayR"
SERVICE_FILE="/etc/systemd/system/XrayR.service"

cur_dir="$(pwd)"

[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain}必须使用 root 用户运行此脚本！" && exit 1

check_release() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif grep -Eqi "debian" /etc/issue 2>/dev/null; then
        release="debian"
    elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null; then
        release="ubuntu"
    elif grep -Eqi "centos|red hat|redhat" /proc/version 2>/dev/null; then
        release="centos"
    elif grep -Eqi "debian" /proc/version 2>/dev/null; then
        release="debian"
    elif grep -Eqi "ubuntu" /proc/version 2>/dev/null; then
        release="ubuntu"
    else
        echo -e "${red}未检测到系统版本${plain}"
        exit 1
    fi
}

check_arch() {
    raw_arch="$(uname -m)"

    case "$raw_arch" in
        x86_64|amd64)
            arch="64"
            ;;
        aarch64|arm64)
            arch="arm64-v8a"
            ;;
        armv7l|armv7)
            arch="arm32-v7a"
            ;;
        armv6l|armv6)
            arch="arm32-v6"
            ;;
        i386|i686)
            arch="32"
            ;;
        *)
            echo -e "${red}暂不支持该架构：${raw_arch}${plain}"
            echo -e "${yellow}请确认仓库是否存在对应文件，例如：XrayR-linux-${raw_arch}.zip${plain}"
            exit 1
            ;;
    esac

    echo -e "检测架构：${green}${raw_arch}${plain} -> 使用文件：${green}XrayR-linux-${arch}.zip${plain}"
}

install_base() {
    if [[ "$release" == "centos" ]]; then
        yum install -y epel-release
        yum install -y wget curl unzip tar crontabs socat
    else
        apt update -y
        apt install -y wget curl unzip tar cron socat
    fi
}

check_status() {
    if [[ ! -f "$SERVICE_FILE" ]]; then
        return 2
    fi

    if systemctl is-active --quiet XrayR; then
        return 0
    else
        return 1
    fi
}

create_manage_script() {
    cat > /usr/bin/XrayR <<'EOF'
#!/bin/bash

case "$1" in
    start)
        systemctl start XrayR
        ;;
    stop)
        systemctl stop XrayR
        ;;
    restart)
        systemctl restart XrayR
        ;;
    status)
        systemctl status XrayR --no-pager -l
        ;;
    enable)
        systemctl enable XrayR
        ;;
    disable)
        systemctl disable XrayR
        ;;
    log)
        journalctl -u XrayR.service -e --no-pager -f
        ;;
    config)
        vi /etc/XrayR/config.yml
        systemctl restart XrayR
        ;;
    version)
        /usr/local/XrayR/XrayR version
        ;;
    uninstall)
        systemctl stop XrayR
        systemctl disable XrayR
        rm -f /etc/systemd/system/XrayR.service
        systemctl daemon-reload
        systemctl reset-failed
        rm -rf /usr/local/XrayR
        rm -rf /etc/XrayR
        rm -f /usr/bin/XrayR /usr/bin/xrayr
        echo "XrayR 已卸载"
        ;;
    *)
        echo "XrayR 管理脚本使用方法："
        echo "------------------------------------------"
        echo "XrayR start      - 启动 XrayR"
        echo "XrayR stop       - 停止 XrayR"
        echo "XrayR restart    - 重启 XrayR"
        echo "XrayR status     - 查看状态"
        echo "XrayR enable     - 设置开机自启"
        echo "XrayR disable    - 取消开机自启"
        echo "XrayR log        - 查看日志"
        echo "XrayR config     - 编辑配置"
        echo "XrayR version    - 查看版本"
        echo "XrayR uninstall  - 卸载 XrayR"
        echo "------------------------------------------"
        ;;
esac
EOF

    chmod +x /usr/bin/XrayR
    ln -sf /usr/bin/XrayR /usr/bin/xrayr
}

install_XrayR() {
    is_new_install=0

    echo -e "${green}开始安装 XrayR${plain}"

    systemctl stop XrayR >/dev/null 2>&1

    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"

    cd "$INSTALL_DIR" || exit 1

    echo -e "${green}下载 XrayR-linux-${arch}.zip${plain}"

    wget -q --no-check-certificate -O XrayR-linux.zip "${REPO_RAW}/XrayR-linux-${arch}.zip"

    if [[ $? -ne 0 || ! -s XrayR-linux.zip ]]; then
        echo -e "${red}下载 XrayR-linux-${arch}.zip 失败，请检查仓库文件是否存在：${REPO_RAW}/XrayR-linux-${arch}.zip${plain}"
        exit 1
    fi

    unzip -o XrayR-linux.zip
    rm -f XrayR-linux.zip

    if [[ ! -f "$INSTALL_DIR/XrayR" ]]; then
        echo -e "${red}解压后没有找到 $INSTALL_DIR/XrayR，请检查 zip 包内容${plain}"
        exit 1
    fi

    chmod +x "$INSTALL_DIR/XrayR"

    echo -e "${green}写入 systemd 服务文件${plain}"

    wget -q --no-check-certificate -O "$SERVICE_FILE" "${REPO_RAW}/XrayR.service"

    if [[ $? -ne 0 || ! -s "$SERVICE_FILE" ]]; then
        echo -e "${yellow}远程 service 下载失败，使用内置 service${plain}"

        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=XrayR Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/XrayR/
ExecStart=/usr/local/XrayR/XrayR --config /etc/XrayR/config.yml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable XrayR

    echo -e "${green}复制基础配置文件${plain}"

    [[ -f geoip.dat ]] && cp -f geoip.dat "$CONFIG_DIR/"
    [[ -f geosite.dat ]] && cp -f geosite.dat "$CONFIG_DIR/"

    if [[ ! -f "$CONFIG_DIR/config.yml" ]]; then
        is_new_install=1
        [[ -f config.yml ]] && cp -f config.yml "$CONFIG_DIR/"
    fi

    [[ ! -f "$CONFIG_DIR/dns.json" && -f dns.json ]] && cp -f dns.json "$CONFIG_DIR/"
    [[ ! -f "$CONFIG_DIR/route.json" && -f route.json ]] && cp -f route.json "$CONFIG_DIR/"
    [[ ! -f "$CONFIG_DIR/custom_outbound.json" && -f custom_outbound.json ]] && cp -f custom_outbound.json "$CONFIG_DIR/"
    [[ ! -f "$CONFIG_DIR/custom_inbound.json" && -f custom_inbound.json ]] && cp -f custom_inbound.json "$CONFIG_DIR/"

    if [[ ! -e "$CONFIG_DIR/rulelist" && -e rulelist ]]; then
        cp -rf rulelist "$CONFIG_DIR/"
    fi

    create_manage_script

    echo -e "${green}XrayR 安装完成，已设置开机自启${plain}"

    if [[ "$is_new_install" == "1" ]]; then
        echo ""
        echo -e "${yellow}检测到是全新安装，已复制默认 config.yml，请先修改配置：${plain}"
        echo -e "${green}vi /etc/XrayR/config.yml${plain}"
        echo ""
        echo -e "配置完成后启动："
        echo -e "${green}systemctl start XrayR${plain}"
        echo -e "或者："
        echo -e "${green}XrayR start${plain}"
    else
        systemctl restart XrayR
        sleep 2

        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}XrayR 启动成功${plain}"
        else
            echo -e "${red}XrayR 可能启动失败，请使用下面命令查看日志：${plain}"
            echo -e "${yellow}journalctl -u XrayR.service -e --no-pager -l${plain}"
        fi
    fi

    cd "$cur_dir" || exit 0
}

check_release
check_arch
install_base
install_XrayR
