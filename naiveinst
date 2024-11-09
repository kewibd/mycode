#!/bin/bash

# 定义一些常量
CADDYFILE_PATH="/etc/caddy/Caddyfile"
CADDY_SERVICE_PATH="/etc/systemd/system/caddy.service"
SCRIPT_PATH="$(realpath $0)"

# 获取用户输入的配置
function get_user_input() {
    read -p "请输入已解析的域名 (例如: example.com): " domain
    read -p "请输入您的电子邮件地址 (例如: youremail@example.com): " email
    read -p "请输入您的用户名 (用于 Basic Auth): " username
    read -p "请输入您的密码 (用于 Basic Auth): " password
    read -p "请输入反向代理的目标网址 (例如: https://example2.com): " proxy_url
}

# 获取最新的 Go 版本号并安装
function install_go() {
    LATEST_VERSION=$(curl -s https://go.dev/VERSION?m=text)
    LATEST_VERSION_NUMBER=${LATEST_VERSION//go/}
    
    if command -v go &>/dev/null; then
        INSTALLED_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
        echo "检测到已安装的 Go 版本: $INSTALLED_VERSION"
    else
        INSTALLED_VERSION=""
        echo "未检测到 Go 语言"
    fi

    if [[ "$INSTALLED_VERSION" < "$LATEST_VERSION_NUMBER" || -z "$INSTALLED_VERSION" ]]; then
        echo "Go 版本不满足要求或未安装，开始下载并安装最新的 Go $LATEST_VERSION..."
        wget https://go.dev/dl/${LATEST_VERSION}.linux-amd64.tar.gz -O /tmp/${LATEST_VERSION}.linux-amd64.tar.gz
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf /tmp/${LATEST_VERSION}.linux-amd64.tar.gz
        if ! grep -q "/usr/local/go/bin" ~/.profile; then
            echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.profile
            source ~/.profile
        fi
        echo "Go $LATEST_VERSION_NUMBER 已安装完成！"
    else
        echo "已安装的 Go 版本满足要求，无需更新。"
    fi
}

# 安装并配置 Caddy
function install_caddy() {
    get_user_input

    echo "安装 xcaddy..."
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

    echo "使用 xcaddy 构建 Caddy，并添加 forwardproxy 插件..."
    ~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive

    echo "移动 Caddy 到 /usr/bin 目录并设置可执行权限..."
    sudo mv ./caddy /usr/bin/caddy
    sudo chmod +x /usr/bin/caddy
    sudo setcap cap_net_bind_service=+ep /usr/bin/caddy

    if ! getent group caddy > /dev/null; then
        echo "创建系统组 caddy..."
        sudo groupadd --system caddy
    fi

    if ! id "caddy" &>/dev/null; then
        echo "创建系统用户 caddy..."
        sudo useradd --system \
            --gid caddy \
            --create-home \
            --home-dir /var/lib/caddy \
            --shell /usr/sbin/nologin \
            --comment "Caddy web server" \
            caddy
    fi

    if [ ! -d /etc/caddy ]; then
        echo "创建 /etc/caddy 目录..."
        sudo mkdir -p /etc/caddy
    fi

    echo "创建 Caddyfile 配置文件..."
    cat <<EOL | sudo tee $CADDYFILE_PATH
:443, $domain
tls $email
route {
  forward_proxy {
    basic_auth $username $password
    hide_ip
    hide_via
    probe_resistance
  }
  reverse_proxy $proxy_url {
    header_up Host {upstream_hostport}
  }
}
EOL

    sudo /usr/bin/caddy fmt --overwrite $CADDYFILE_PATH

    echo "创建 caddy.service 文件..."
    cat <<EOL | sudo tee $CADDY_SERVICE_PATH
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config $CADDYFILE_PATH
ExecReload=/usr/bin/caddy reload --config $CADDYFILE_PATH
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable caddy
    sudo systemctl start caddy

    echo "Caddy 安装和配置完成！"
}

# 修改 Caddyfile 配置
function modify_caddyfile() {
    echo "当前 Caddyfile 配置："
    cat $CADDYFILE_PATH
    echo "-----------------------------------"
    echo "请重新输入您要修改的 Caddyfile 配置："
    get_user_input

    echo "更新 Caddyfile 配置..."
    cat <<EOL | sudo tee $CADDYFILE_PATH
:443, $domain
tls $email
route {
  forward_proxy {
    basic_auth $username $password
    hide_ip
    hide_via
    probe_resistance
  }
  reverse_proxy $proxy_url {
    header_up Host {upstream_hostport}
  }
}
EOL

    sudo /usr/bin/caddy fmt --overwrite $CADDYFILE_PATH
    sudo systemctl reload caddy

    echo "Caddyfile 已更新并生效！"
}

# 修改时区
function change_timezone() {
    echo "可用时区列表："
    timedatectl list-timezones
    read -p "请输入要设置的时区 (例如: Asia/Shanghai): " timezone
    sudo timedatectl set-timezone $timezone
    echo "时区已更改为 $timezone"
}

# 显示配置信息
function show_info() {
    echo "-----------------------------------"
    echo "域名        : $domain"
    echo "电子邮件    : $email"
    echo "用户名      : $username"
    echo "密码        : $password"
    echo "反代目标网址: $proxy_url"
    echo "Caddyfile路径 : $CADDYFILE_PATH"
    echo "caddy.service路径 : $CADDY_SERVICE_PATH"
    echo "脚本路径    : $SCRIPT_PATH"
    echo "-----------------------------------"
}

# 显示菜单并执行操作
while true; do
    echo "请选择一个选项："
    echo "1) 仅安装 Go 语言"
    echo "2) 仅安装 Caddy"
    echo "3) 全部安装"
    echo "4) 修改 Caddyfile"
    echo "5) 修改时区"
    echo "6) 显示配置信息"
    echo "7) 退出脚本"
    read -p "输入您的选择: " choice

    case $choice in
        1) install_go ;;
        2) install_caddy ;;
        3) install_go; install_caddy ;;
        4) modify_caddyfile ;;
        5) change_timezone ;;
        6) show_info ;;
        7) exit ;;
        *) echo "无效的选择，请重试。" ;;
    esac
done
