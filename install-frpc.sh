#!/bin/bash
set -e

FRP_VERSION="0.63.0"
INSTALL_DIR="/opt/frp"
SYSTEMD_DIR="/etc/systemd/system"

echo "=== FRPS Simple Installer ==="
echo "1) Install FRPS"
echo "2) Uninstall FRPS"
read -p "Choose an option [1/2]: " OPTION

install_frps() {
    echo ">>> Installing FRPS..."

    apt-get update -y
    apt-get install -y wget tar

    wget -q https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz
    mkdir -p $INSTALL_DIR
    tar -zxvf frp_${FRP_VERSION}_linux_amd64.tar.gz -C $INSTALL_DIR --strip-components=1
    rm -f frp_${FRP_VERSION}_linux_amd64.tar.gz

    echo "FRPS installed to $INSTALL_DIR"

    # Ask for bind port and token
    read -p "Enter bind port [default 7000]: " BIND_PORT
    BIND_PORT=${BIND_PORT:-7000}
    read -p "Enter token: " TOKEN

    # Create frps.ini (simple)
    cat > $INSTALL_DIR/frps.ini <<EOF
[common]
bind_port = $BIND_PORT
token = $TOKEN
EOF

    # Create systemd service
    cat > $SYSTEMD_DIR/frps.service <<EOF
[Unit]
Description=FRP Server
After=network.target

[Service]
Type=simple
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
    1) install_frps ;;
    2) uninstall_frps ;;
    *) echo "Invalid option"; exit 1 ;;
esac
