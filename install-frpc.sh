#!/bin/bash
set -e

FRP_VERSION="0.54.0"  # Updated to a stable version
INSTALL_DIR="/opt/frp"
SYSTEMD_DIR="/etc/systemd/system"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Use sudo." >&2
    exit 1
fi

echo "=== FRP Installer ==="
echo "1) Install FRPC (Client)"
echo "2) Uninstall FRPC (Client)"
echo "3) Install FRPS (Server)"
echo "4) Uninstall FRPS (Server)"
read -p "Choose an option [1-4]: " OPTION

install_frpc() {
    echo "Installing FRP Client..."
    
    # Check if already installed
    if [[ -f "$SYSTEMD_DIR/frpc.service" ]]; then
        echo "FRPC appears to be already installed. Please uninstall first." >&2
        exit 1
    fi

    # Install dependencies
    if ! command -v wget &> /dev/null || ! command -v tar &> /dev/null; then
        echo "Installing dependencies..."
        apt-get update -y
        apt-get install -y wget tar
    fi

    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="arm"
            ;;
        *)
            echo "Unsupported architecture: $ARCH" >&2
            exit 1
            ;;
    esac

    # Download and extract FRP
    echo "Downloading FRP v${FRP_VERSION} for ${ARCH}..."
    if ! wget -q "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz" -O /tmp/frp.tar.gz; then
        echo "Failed to download FRP. Check version and network." >&2
        exit 1
    fi

    mkdir -p "$INSTALL_DIR"
    tar -xzf /tmp/frp.tar.gz -C "$INSTALL_DIR" --strip-components=1
    rm -f /tmp/frp.tar.gz

    # Get configuration
    echo "Configuring FRPC..."
    read -p "FRPS server IP: " SERVER_IP
    read -p "FRPS server port [7000]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7000}
    read -s -p "Token: " TOKEN
    echo

    # Create frpc.ini
    cat > "$INSTALL_DIR/frpc.ini" <<EOF
[common]
server_addr = $SERVER_IP
server_port = $SERVER_PORT
token = $TOKEN

# Add your services here. Example:
# [ssh]
# type = tcp
# local_ip = 127.0.0.1
# local_port = 22
# remote_port = 6000
EOF

    echo "FRPC configuration saved to $INSTALL_DIR/frpc.ini"

    # Create systemd service
    cat > "$SYSTEMD_DIR/frpc.service" <<EOF
[Unit]
Description=FRP Client
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=$INSTALL_DIR/frpc -c $INSTALL_DIR/frpc.ini
ExecReload=/bin/kill -HUP \$MAINPID
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    # Set permissions
    chmod +x "$INSTALL_DIR/frpc"
    chmod 644 "$INSTALL_DIR/frpc.ini"

    # Start service
    systemctl daemon-reload
    systemctl enable frpc
    systemctl start frpc

    echo "Waiting for service to start..."
    sleep 2

    if systemctl is-active --quiet frpc; then
        echo "FRPC installed and started successfully!"
        systemctl status frpc --no-pager
    else
        echo "FRPC failed to start. Check logs with: journalctl -u frpc" >&2
        exit 1
    fi
}

uninstall_frpc() {
    echo "Uninstalling FRPC..."
    
    if systemctl is-active --quiet frpc; then
        systemctl stop frpc
    fi
    
    if systemctl is-enabled --quiet frpc 2>/dev/null; then
        systemctl disable frpc
    fi
    
    rm -f "$SYSTEMD_DIR/frpc.service"
    systemctl daemon-reload
    
    # Remove only frpc related files, keep frps if exists
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -f "$INSTALL_DIR/frpc" "$INSTALL_DIR/frpc.ini"
        # Remove directory only if no frps files exist
        if ! ls "$INSTALL_DIR"/frps* >/dev/null 2>&1; then
            rm -rf "$INSTALL_DIR"
        fi
    fi
    
    echo "FRPC uninstalled successfully."
}

install_frps() {
    echo "Installing FRP Server..."
    
    # Check if already installed
    if [[ -f "$SYSTEMD_DIR/frps.service" ]]; then
        echo "FRPS appears to be already installed. Please uninstall first." >&2
        exit 1
    fi

    # Install dependencies
    if ! command -v wget &> /dev/null || ! command -v tar &> /dev/null; then
        echo "Installing dependencies..."
        apt-get update -y
        apt-get install -y wget tar
    fi

    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        armv7l)
            ARCH="arm"
            ;;
        *)
            echo "Unsupported architecture: $ARCH" >&2
            exit 1
            ;;
    esac

    # Download and extract FRP
    echo "Downloading FRP v${FRP_VERSION} for ${ARCH}..."
    if ! wget -q "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz" -O /tmp/frp.tar.gz; then
        echo "Failed to download FRP. Check version and network." >&2
        exit 1
    fi

    mkdir -p "$INSTALL_DIR"
    tar -xzf /tmp/frp.tar.gz -C "$INSTALL_DIR" --strip-components=1
    rm -f /tmp/frp.tar.gz

    # Get configuration
    echo "Configuring FRPS..."
    read -p "Bind port [7000]: " BIND_PORT
    BIND_PORT=${BIND_PORT:-7000}
    read -p "Dashboard port [7500]: " DASHBOARD_PORT
    DASHBOARD_PORT=${DASHBOARD_PORT:-7500}
    read -s -p "Token: " TOKEN
    echo
    read -p "Dashboard user [admin]: " DASHBOARD_USER
    DASHBOARD_USER=${DASHBOARD_USER:-admin}
    read -s -p "Dashboard password: " DASHBOARD_PASSWORD
    echo

    # Create frps.ini
    cat > "$INSTALL_DIR/frps.ini" <<EOF
[common]
bind_port = $BIND_PORT
token = $TOKEN
dashboard_port = $DASHBOARD_PORT
dashboard_user = $DASHBOARD_USER
dashboard_pwd = $DASHBOARD_PASSWORD
EOF

    echo "FRPS configuration saved to $INSTALL_DIR/frps.ini"

    # Create systemd service
    cat > "$SYSTEMD_DIR/frps.service" <<EOF
[Unit]
Description=FRP Server
After=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=$INSTALL_DIR/frps -c $INSTALL_DIR/frps.ini
ExecReload=/bin/kill -HUP \$MAINPID
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    # Set permissions
    chmod +x "$INSTALL_DIR/frps"
    chmod 644 "$INSTALL_DIR/frps.ini"

    # Start service
    systemctl daemon-reload
    systemctl enable frps
    systemctl start frps

    echo "Waiting for service to start..."
    sleep 2

    if systemctl is-active --quiet frps; then
        echo "FRPS installed and started successfully!"
        echo "Dashboard available at: http://$(curl -s ifconfig.me):$DASHBOARD_PORT"
        systemctl status frps --no-pager
    else
        echo "FRPS failed to start. Check logs with: journalctl -u frps" >&2
        exit 1
    fi
}

uninstall_frps() {
    echo "Uninstalling FRPS..."
    
    if systemctl is-active --quiet frps; then
        systemctl stop frps
    fi
    
    if systemctl is-enabled --quiet frps 2>/dev/null; then
        systemctl disable frps
    fi
    
    rm -f "$SYSTEMD_DIR/frps.service"
    systemctl daemon-reload
    
    # Remove only frps related files, keep frpc if exists
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -f "$INSTALL_DIR/frps" "$INSTALL_DIR/frps.ini"
        # Remove directory only if no frpc files exist
        if ! ls "$INSTALL_DIR"/frpc* >/dev/null 2>&1; then
            rm -rf "$INSTALL_DIR"
        fi
    fi
    
    echo "FRPS uninstalled successfully."
}

case $OPTION in
    1) install_frpc ;;
    2) uninstall_frpc ;;
    3) install_frps ;;
    4) uninstall_frps ;;
    *) echo "Invalid option"; exit 1 ;;
esac
