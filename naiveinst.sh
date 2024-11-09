#!/bin/bash

# 定义安装 Go 的函数
function install_go() {
    # 获取 Go 的最新版本号
    LATEST_VERSION=$(curl -s https://go.dev/dl/ | grep -oP 'go[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    LATEST_VERSION_NUMBER=${LATEST_VERSION//go/}

    # 检查是否已安装 Go
    if command -v go &>/dev/null; then
        INSTALLED_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
        echo "检测到已安装的 Go 版本: $INSTALLED_VERSION"
    else
        INSTALLED_VERSION=""
        echo "未检测到 Go 语言"
    fi

    # 如果 Go 版本较低或未安装，下载并安装最新版本
    if [[ "$INSTALLED_VERSION" < "$LATEST_VERSION_NUMBER" || -z "$INSTALLED_VERSION" ]]; then
        echo "Go 版本不满足要求或未安装，开始下载并安装 Go $LATEST_VERSION..."

        # 构建 Go 下载 URL
        DOWNLOAD_URL="https://go.dev/dl/${LATEST_VERSION}.linux-amd64.tar.gz"
        wget $DOWNLOAD_URL -O /tmp/go${LATEST_VERSION_NUMBER}.linux-amd64.tar.gz

        # 移除旧的 Go 安装
        sudo rm -rf /usr/local/go

        # 解压并安装
        sudo tar -C /usr/local -xzf /tmp/go${LATEST_VERSION_NUMBER}.linux-amd64.tar.gz

        # 临时添加 Go 的路径到当前 shell 会话中
        echo "export PATH=\$PATH:/usr/local/go/bin" | sudo tee -a /etc/profile > /dev/null
        source /etc/profile

        # 确保 Go 在当前 shell 会话生效
        echo "Go 路径已添加到当前会话，您可以立即使用 Go："
        go version
    else
        echo "已安装的 Go 版本满足要求，无需更新。"
    fi
}

# 安装 Caddy 的函数
function install_caddy() {
    # 使用 xcaddy 构建 Caddy
    echo "使用 xcaddy 构建 Caddy..." 
                go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
                ~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive
    
    # 检查 Caddy 是否在当前目录下
    if [ -f ./caddy ]; then
        echo "Caddy 构建成功！"
        
        # 删除可能存在的符号链接并移动 Caddy 到 /usr/bin/ 目录
        sudo rm -f /usr/bin/caddy
        sudo mv ./caddy /usr/bin/caddy
        
        # 检查 Caddy 是否成功移动
        if [ -f /usr/bin/caddy ]; then
            echo "Caddy 已成功移动到 /usr/bin/caddy"
            
            # 设置 CAP_NET_BIND_SERVICE 权限
            sudo setcap cap_net_bind_service=+ep /usr/bin/caddy
            if [ $? -eq 0 ]; then
                echo "Caddy 设置权限成功！"
            else
                echo "设置权限失败，请检查 Caddy 可执行文件是否存在，并确保其不是符号链接。"
            fi
                 # 配置防火墙，打开 80 和 443 端口
            echo "配置防火墙，打开 80 和 443 端口..."
            sudo ufw allow 80/tcp
            sudo ufw allow 443/tcp
            echo "Caddy 安装完成，防火墙端口已配置！"
        else
            echo "Caddy 文件未成功移动到 /usr/bin/caddy，请检查路径。"
        fi
    else
        echo "Caddy 文件未生成，构建可能失败。"
    fi
}

# 创建 Caddyfile 的函数
function create_caddyfile() {
    # 提示用户输入域名、邮箱、用户名、密码和反代网址
    read -p "请输入你的域名 (例如: example.com): " domain
    read -p "请输入你的邮箱 (用于 TLS 证书): " email
    read -p "请输入你的用户名 (用于代理认证): " username
    read -p "请输入你的密码 (用于代理认证): " password
    read -p "请输入反向代理的网址 (例如: https://example2.com): " proxy_url

    # 检查 /etc/caddy 目录是否存在，如果不存在则创建
    if [ ! -d "/etc/caddy" ]; then
        sudo mkdir -p /etc/caddy
    fi

    # 创建 Caddyfile 内容
    CADDYFILE_CONTENT=":443, $domain
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
}"

    # 写入 Caddyfile
    echo "$CADDYFILE_CONTENT" | sudo tee /etc/caddy/Caddyfile > /dev/null

    # 格式化 Caddyfile
    sudo caddy fmt --overwrite /etc/caddy/Caddyfile

    echo "Caddyfile 已创建并格式化！"
}

# 创建 Caddy 服务文件的函数
function create_caddy_service() {
    # 确保 caddy 组和用户存在
    echo "检查并创建 caddy 用户和组..."
    if ! getent group caddy > /dev/null; then
        sudo groupadd --system caddy
        echo "Caddy 组已创建。"
    else
        echo "Caddy 组已存在。"
    fi

    if ! id -u caddy > /dev/null 2>&1; then
        sudo useradd --system \
            --gid caddy \
            --create-home \
            --home-dir /var/lib/caddy \
            --shell /usr/sbin/nologin \
            --comment "Caddy web server" \
            caddy
        echo "Caddy 用户已创建。"
    else
        echo "Caddy 用户已存在。"
    fi

    # 创建 /etc/systemd/system/caddy.service 文件
    echo "创建 Caddy systemd 服务文件..."
    sudo bash -c 'cat <<EOF > /etc/systemd/system/caddy.service
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
User=caddy
Group=caddy
ExecStart=/usr/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/bin/caddy reload --config /etc/caddy/Caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF'
    echo "Caddy 服务文件已创建。"

    # 重新加载 systemd 并启用 Caddy 服务
    sudo systemctl daemon-reload
    sudo systemctl enable caddy
    echo "Caddy 服务已启用。"
}

# 显示菜单
function show_menu() {
    echo "请选择操作："
    echo "1. 安装 Go 语言"
    echo "2. 安装 Caddy"
    echo "3. 创建 Caddyfile"
    echo "4. 创建并启动 Caddy 服务"
    echo "5. 全部安装"
    echo "6. 退出"
}

# 主程序逻辑
while true; do
    show_menu
    read -p "请输入选项: " choice
    case $choice in
        1)
            install_go
            ;;
        2)
            install_caddy
            ;;
        3)
            create_caddyfile
            ;;
        4)
            create_caddy_service
            ;;
        5)
            install_go
            install_caddy
            create_caddyfile
            create_caddy_service
            ;;
        6)
            echo "退出脚本"
            exit 0
            ;;
        *)
            echo "无效选项，请重新选择！"
            ;;
    esac
done
