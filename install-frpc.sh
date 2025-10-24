#!/bin/bash
set -e

FRP_VERSION="0.54.0"
INSTALL_DIR="/opt/frp"
SYSTEMD_DIR="/etc/systemd/system"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root. Use: sudo bash $0${NC}" >&2
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect architecture
detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l|armv6l) echo "arm" ;;
        *) echo "unsupported" ;;
    esac
}

# Function to install dependencies
install_dependencies() {
    if ! command_exists wget || ! command_exists tar; then
        echo "Installing dependencies..."
        apt-get update -y
        apt-get install -y wget tar
    fi
}

# Function to download and extract FRP
download_frp() {
    local arch="$1"
    echo "Downloading FRP v${FRP_VERSION} for ${arch}..."
    
    if ! wget -q "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${arch}.tar.gz" -O /tmp/frp.tar.gz; then
        echo -e "${RED}Failed to download FRP. Check version and network connection.${NC}" >&2
        exit 1
    fi

    mkdir -p "$INSTALL_DIR"
    tar -xzf /tmp/frp.tar.gz -C /tmp/
    cp /tmp/frp_${FRP_VERSION}_linux_${arch}/frp* "$INSTALL_DIR/" 2>/dev/null || true
    rm -rf /tmp/frp.tar.gz /tmp/frp_${FRP_VERSION}_linux_${arch}
}

# Function to install FRPC
install_frpc() {
    echo -e "${GREEN}Installing FRP Client...${NC}"
    
    # Check if already installed
    if [[ -f "$SYSTEMD_DIR/frpc.service" ]]; then
        echo -e "${YELLOW}FRPC appears to be already installed. Please uninstall first.${NC}" >&2
        exit 1
    fi

    local arch
    arch=$(detect_arch)
    if [[ "$arch" == "unsupported" ]]; then
        echo -e "${RED}Unsupported architecture: $(uname -m)${NC}" >&2
        exit 1
    fi

    install_dependencies
    download_frp "$arch"

    # Get configuration
    echo
    echo "FRPC Configuration:"
    read -p "FRPS server IP: " SERVER_IP
    read -p "FRPS server port [7000]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7000}
    read -s -p "Token: " TOKEN
    echo

    # Create frpc.ini
    cat > "$INSTALL_DIR/frpc.ini" << EOF
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
    cat > "$SYSTEMD_DIR/frpc.service" << EOF
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
    sleep 3

    if systemctl is-active --quiet frpc; then
        echo -e "${GREEN}FRPC installed and started successfully!${NC}"
        echo -e "${YELLOW}Service status:${NC}"
        systemctl status frpc --no-pager
        echo
        echo -e "${YELLOW}Next steps:${NC}"
        echo "1. Edit $INSTALL_DIR/frpc.ini to add your services"
        echo "2. Run: systemctl restart frpc"
        echo "3. Check logs: journalctl -u frpc -f"
    else
        echo -e "${RED}FRPC failed to start. Check logs with: journalctl -u frpc${NC}" >&2
        exit 1
    fi
}

# Function to uninstall FRPC
uninstall_frpc() {
    echo -e "${YELLOW}Uninstalling FRPC...${NC}"
    
    if systemctl is-active --quiet frpc; then
        systemctl stop frpc
    fi
    
    if systemctl is-enabled --quiet frpc 2>/dev/null; then
        systemctl disable frpc
    fi
    
    rm -f "$SYSTEMD_DIR/frpc.service"
    systemctl daemon-reload
    
    # Remove only frpc related files
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -f "$INSTALL_DIR/frpc" "$INSTALL_DIR/frpc.ini"
        # Remove directory only if empty
        if [[ -z "$(ls -A "$INSTALL_DIR")" ]]; then
            rm -rf "$INSTALL_DIR"
        fi
    fi
    
    echo -e "${GREEN}FRPC uninstalled successfully.${NC}"
}

# Function to install FRPS
install_frps() {
    echo -e "${GREEN}Installing FRP Server...${NC}"
    
    # Check if already installed
    if [[ -f "$SYSTEMD_DIR/frps.service" ]]; then
        echo -e "${YELLOW}FRPS appears to be already installed. Please uninstall first.${NC}" >&2
        exit 1
    fi

    local arch
    arch=$(detect_arch)
    if [[ "$arch" == "unsupported" ]]; then
        echo -e "${RED}Unsupported architecture: $(uname -m)${NC}" >&2
        exit 1
    fi

    install_dependencies
    download_frp "$arch"

    # Get configuration
    echo
    echo "FRPS Configuration:"
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
    cat > "$INSTALL_DIR/frps.ini" << EOF
[common]
bind_port = $BIND_PORT
token = $TOKEN
dashboard_port = $DASHBOARD_PORT
dashboard_user = $DASHBOARD_USER
dashboard_pwd = $DASHBOARD_PASSWORD
EOF

    echo "FRPS configuration saved to $INSTALL_DIR/frps.ini"

    # Create systemd service
    cat > "$SYSTEMD_DIR/frps.service" << EOF
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
    sleep 3

    if systemctl is-active --quiet frps; then
        echo -e "${GREEN}FRPS installed and started successfully!${NC}"
        echo
        echo -e "${YELLOW}Dashboard available at:${NC} http://your-server-ip:$DASHBOARD_PORT"
        echo -e "${YELLOW}Username:${NC} $DASHBOARD_USER"
        echo -e "${YELLOW}Bind port:${NC} $BIND_PORT"
        echo
        systemctl status frps --no-pager
    else
        echo -e "${RED}FRPS failed to start. Check logs with: journalctl -u frps${NC}" >&2
        exit 1
    fi
}

# Function to uninstall FRPS
uninstall_frps() {
    echo -e "${YELLOW}Uninstalling FRPS...${NC}"
    
    if systemctl is-active --quiet frps; then
        systemctl stop frps
    fi
    
    if systemctl is-enabled --quiet frps 2>/dev/null; then
        systemctl disable frps
    fi
    
    rm -f "$SYSTEMD_DIR/frps.service"
    systemctl daemon-reload
    
    # Remove only frps related files
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -f "$INSTALL_DIR/frps" "$INSTALL_DIR/frps.ini"
        # Remove directory only if empty
        if [[ -z "$(ls -A "$INSTALL_DIR")" ]]; then
            rm -rf "$INSTALL_DIR"
        fi
    fi
    
    echo -e "${GREEN}FRPS uninstalled successfully.${NC}"
}

# Main menu
echo "=== FRP Installer ==="
echo "1) Install FRPC (Client)"
echo "2) Uninstall FRPC (Client)"
echo "3) Install FRPS (Server)"
echo "4) Uninstall FRPS (Server)"
read -p "Choose an option [1-4]: " OPTION

case $OPTION in
    1) install_frpc ;;
    2) uninstall_frpc ;;
    3) install_frps ;;
    4) uninstall_frps ;;
    *) 
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac
