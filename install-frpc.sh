#!/bin/bash
set -e

FRP_VERSION="0.54.0"
INSTALL_DIR="/opt/frp"
SYSTEMD_DIR="/etc/systemd/system"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Function to configure multiple ports
configure_ports() {
    local config_file="$1"
    
    echo
    echo -e "${BLUE}=== Port Configuration ===${NC}"
    
    # SSH Port configuration
    echo
    echo -e "${YELLOW}SSH Port Configuration:${NC}"
    read -p "Enable SSH port forwarding? [y/N]: " ENABLE_SSH
    if [[ "$ENABLE_SSH" =~ ^[Yy]$ ]]; then
        read -p "Local SSH port [22]: " LOCAL_SSH_PORT
        LOCAL_SSH_PORT=${LOCAL_SSH_PORT:-22}
        read -p "Remote SSH port [6000]: " REMOTE_SSH_PORT
        REMOTE_SSH_PORT=${REMOTE_SSH_PORT:-6000}
        
        cat >> "$config_file" << EOF

# SSH Access
[ssh]
type = tcp
local_ip = 127.0.0.1
local_port = $LOCAL_SSH_PORT
remote_port = $REMOTE_SSH_PORT
EOF
    fi

    # Single port configuration
    echo
    echo -e "${YELLOW}Single TCP Ports:${NC}"
    read -p "Do you want to add single TCP ports? [y/N]: " ADD_SINGLE_PORTS
    while [[ "$ADD_SINGLE_PORTS" =~ ^[Yy]$ ]]; do
        read -p "Local port: " LOCAL_PORT
        read -p "Remote port: " REMOTE_PORT
        read -p "Service name (e.g., web, database): " SERVICE_NAME
        
        if [[ -n "$LOCAL_PORT" && -n "$REMOTE_PORT" && -n "$SERVICE_NAME" ]]; then
            cat >> "$config_file" << EOF

# $SERVICE_NAME Service
[$SERVICE_NAME]
type = tcp
local_ip = 127.0.0.1
local_port = $LOCAL_PORT
remote_port = $REMOTE_PORT
EOF
        fi
        
        read -p "Add another single port? [y/N]: " ADD_SINGLE_PORTS
    done

    # Port range configuration
    echo
    echo -e "${YELLOW}Port Ranges:${NC}"
    read -p "Do you want to add port ranges? [y/N]: " ADD_RANGES
    while [[ "$ADD_RANGES" =~ ^[Yy]$ ]]; do
        echo
        read -p "Starting local port: " START_LOCAL
        read -p "Ending local port: " END_LOCAL
        read -p "Starting remote port: " START_REMOTE
        read -p "Ending remote port: " END_REMOTE
        read -p "Range name (e.g., games, apps): " RANGE_NAME
        
        local count_local=$((END_LOCAL - START_LOCAL + 1))
        local count_remote=$((END_REMOTE - START_REMOTE + 1))
        
        if [[ "$count_local" -ne "$count_remote" ]]; then
            echo -e "${RED}Error: Local and remote port ranges must have the same number of ports.${NC}"
            read -p "Add another port range? [y/N]: " ADD_RANGES
            continue
        fi
        
        if [[ "$count_local" -gt 100 ]]; then
            echo -e "${YELLOW}Warning: You're adding $count_local ports. This might be too many.${NC}"
            read -p "Continue? [y/N]: " CONFIRM
            if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
                read -p "Add another port range? [y/N]: " ADD_RANGES
                continue
            fi
        fi
        
        cat >> "$config_file" << EOF

# $RANGE_NAME Port Range
EOF
        
        for ((i=0; i<count_local; i++)); do
            local_port=$((START_LOCAL + i))
            remote_port=$((START_REMOTE + i))
            cat >> "$config_file" << EOF
[${RANGE_NAME}_$((i+1))]
type = tcp
local_ip = 127.0.0.1
local_port = $local_port
remote_port = $remote_port
EOF
        done
        
        echo -e "${GREEN}Added $count_local ports in range $START_LOCAL-$END_LOCAL → $START_REMOTE-$END_REMOTE${NC}"
        read -p "Add another port range? [y/N]: " ADD_RANGES
    done

    # HTTP/HTTPS configuration
    echo
    echo -e "${YELLOW}HTTP/HTTPS Services:${NC}"
    read -p "Do you want to add HTTP/HTTPS services? [y/N]: " ADD_HTTP
    while [[ "$ADD_HTTP" =~ ^[Yy]$ ]]; do
        read -p "Service type [http/https]: " SERVICE_TYPE
        SERVICE_TYPE=${SERVICE_TYPE:-http}
        read -p "Local port: " LOCAL_PORT
        read -p "Custom domain (optional): " CUSTOM_DOMAIN
        read -p "Subdomain (optional): " SUBDOMAIN
        
        if [[ -n "$LOCAL_PORT" ]]; then
            cat >> "$config_file" << EOF

# Web Service - $SERVICE_TYPE
[web_$LOCAL_PORT]
type = $SERVICE_TYPE
local_ip = 127.0.0.1
local_port = $LOCAL_PORT
EOF
            if [[ -n "$CUSTOM_DOMAIN" ]]; then
                echo "custom_domains = $CUSTOM_DOMAIN" >> "$config_file"
            fi
            if [[ -n "$SUBDOMAIN" ]]; then
                echo "subdomain = $SUBDOMAIN" >> "$config_file"
            fi
        fi
        
        read -p "Add another HTTP/HTTPS service? [y/N]: " ADD_HTTP
    done
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

    # Get basic configuration
    echo
    echo -e "${BLUE}=== Basic FRPC Configuration ===${NC}"
    read -p "FRPS server IP: " SERVER_IP
    read -p "FRPS server port [7000]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7000}
    read -s -p "Token: " TOKEN
    echo

    # Create basic frpc.ini
    cat > "$INSTALL_DIR/frpc.ini" << EOF
[common]
server_addr = $SERVER_IP
server_port = $SERVER_PORT
token = $TOKEN
EOF

    # Configure ports
    configure_ports "$INSTALL_DIR/frpc.ini"

    echo
    echo -e "${GREEN}FRPC configuration saved to $INSTALL_DIR/frpc.ini${NC}"

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
        echo
        echo -e "${YELLOW}=== Configuration Summary ===${NC}"
        echo -e "Server: ${SERVER_IP}:${SERVER_PORT}"
        echo -e "Config file: $INSTALL_DIR/frpc.ini"
        echo -e "Service: systemctl status frpc"
        echo -e "Logs: journalctl -u frpc -f"
        echo
        echo -e "${YELLOW}You can edit the configuration file and restart the service:${NC}"
        echo "nano $INSTALL_DIR/frpc.ini"
        echo "systemctl restart frpc"
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

    # Allow port ranges in firewall
    echo
    echo -e "${YELLOW}Configuring firewall...${NC}"
    if command_exists ufw; then
        ufw allow $BIND_PORT/tcp comment "FRPS bind port"
        ufw allow $DASHBOARD_PORT/tcp comment "FRPS dashboard"
        echo "UFW rules added for ports $BIND_PORT and $DASHBOARD_PORT"
    fi

    # Create frps.ini
    cat > "$INSTALL_DIR/frps.ini" << EOF
[common]
bind_port = $BIND_PORT
token = $TOKEN
dashboard_port = $DASHBOARD_PORT
dashboard_user = $DASHBOARD_USER
dashboard_pwd = $DASHBOARD_PASSWORD

# Allow large port ranges
max_pool_count = 100000
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
        echo -e "${YELLOW}=== Server Information ===${NC}"
        echo -e "Bind Port: $BIND_PORT"
        echo -e "Dashboard: http://your-server-ip:$DASHBOARD_PORT"
        echo -e "Username: $DASHBOARD_USER"
        echo -e "Token: $TOKEN"
        echo
        echo -e "${YELLOW}Client Configuration Example:${NC}"
        echo "[common]"
        echo "server_addr = YOUR_SERVER_IP"
        echo "server_port = $BIND_PORT"
        echo "token = $TOKEN"
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
