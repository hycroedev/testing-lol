#!/bin/bash
set -e

FRP_VERSION="0.65.0"
INSTALL_DIR="/opt/frp"
SYSTEMD_DIR="/etc/systemd/system"

echo "=== FRP Combined Installer ==="
echo "1) Install FRPC (Client)"
echo "2) Uninstall FRPC (Client)"
echo "3) Install FRPS (Server)"
echo "4) Uninstall FRPS (Server)"
read -p "Choose an option [1-4]: " OPTION

install_frpc() {
    echo ">>> Installing FRPC..."

    apt-get update -y
    apt-get install -y wget tar

    wget -q https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz -O /tmp/frp.tar.gz
    mkdir -p $INSTALL_DIR
    tar -zxvf /tmp/frp.tar.gz -C $INSTALL_DIR --strip-components=1
    rm -f /tmp/frp.tar.gz

    echo "FRPC installed to $INSTALL_DIR"

    read -p "Enter FRPS server address: " SERVER_IP
    read -p "Enter FRPS server port [default 7000]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7000}
    read -p "Enter token: " TOKEN

    read -p "Enter starting port (SSH port): " START_PORT
    read -p "Enter ending port: " END_PORT

    {
        echo "[common]"
        echo "server_addr = $SERVER_IP"
        echo "server_port = $SERVER_PORT"
        echo "token = $TOKEN"
    } > "$INSTALL_DIR/frpc.ini"

    {
        echo "[ssh$START_PORT]"
        echo "type = tcp"
        echo "local_ip = 127.0.0.1"
        echo "local_port = 22"
        echo "remote_port = $START_PORT"
    } >> "$INSTALL_DIR/frpc.ini"

    CURRENT_PORT=$((START_PORT + 1))
    while [ $CURRENT_PORT -le $END_PORT ]; do
        {
            echo "[tcp$CURRENT_PORT]"
            echo "type = tcp"
            echo "local_ip = 127.0.0.1"
            echo "local_port = $CURRENT_PORT"
            echo "remote_port = $CURRENT_PORT"
            echo ""
            echo "[udp$CURRENT_PORT]"
            echo "type = udp"
            echo "local_ip = 127.0.0.1"
            echo "local_port = $CURRENT_PORT"
            echo "remote_port = $CURRENT_PORT"
        } >> "$INSTALL_DIR/frpc.ini"
        CURRENT_PORT=$((CURRENT_PORT + 1))
    done

    cat > $SYSTEMD_DIR/frpc.service << EOF
[Unit]
Description=FRP Client
After=network.target

[Service]
Type=simple
Restart=on-failure
RestartSec=5s
ExecStart=$INSTALL_DIR/frpc -c $INSTALL_DIR/frpc.ini
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable frpc
    systemctl restart frpc
    echo "=== FRPC Setup Complete ==="
    systemctl status frpc --no-pager
}

uninstall_frpc() {
    echo ">>> Stopping FRPC service..."
    systemctl stop frpc 2>/dev/null || true
    systemctl disable frpc 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/frpc.service"
    rm -rf "$INSTALL_DIR"
    systemctl daemon-reload
    echo ">>> FRPC fully removed."
}

install_frps() {
    echo ">>> Installing FRPS (Server)..."

    apt-get update -y
    apt-get install -y wget tar

    wget -q https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz -O /tmp/frp.tar.gz
    mkdir -p $INSTALL_DIR
    tar -zxvf /tmp/frp.tar.gz -C $INSTALL_DIR --strip-components=1
    rm -f /tmp/frp.tar.gz

    echo "FRPS installed to $INSTALL_DIR"

    read -p "Enter bind port [default 7000]: " BIND_PORT
    BIND_PORT=${BIND_PORT:-7000}
    read -p "Enter UDP bind port [default 7001]: " BIND_UDP
    BIND_UDP=${BIND_UDP:-7001}
    read -p "Enter token: " TOKEN

    {
        echo "[common]"
        echo "bind_port = $BIND_PORT"
        echo "bind_udp_port = $BIND_UDP"
        echo "token = $TOKEN"
    } > "$INSTALL_DIR/frps.ini"

    cat > $SYSTEMD_DIR/frps.service << EOF
[Unit]
Description=FRP Server
After=network.target

[Service]
Type=simple
User=nobody
Restart=on-failure
RestartSec=5s
ExecStart=$INSTALL_DIR/frps -c $INSTALL_DIR/frps.ini
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable frps
    systemctl restart frps
    echo "=== FRPS Setup Complete ==="
    systemctl status frps --no-pager

    echo ">>> FRPS is now running on:"
    echo "    TCP Port: $BIND_PORT"
    echo "    UDP Port: $BIND_UDP"
    echo ">>> Use this server IP and token for your FRPC clients"
}

uninstall_frps() {
    echo ">>> Stopping FRPS service..."
    systemctl stop frps 2>/dev/null || true
    systemctl disable frps 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/frps.service"
    rm -rf "$INSTALL_DIR"
    systemctl daemon-reload
    echo ">>> FRPS fully removed."
}

case $OPTION in
    1) install_frpc ;;
    2) uninstall_frpc ;;
    3) install_frps ;;
    4) uninstall_frps ;;
    *) echo "Invalid option"; exit 1 ;;
esac
