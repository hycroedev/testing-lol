#!/bin/bash
set -e

FRP_VERSION="0.63.0"
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

    read -p "How many ports do you want to forward? " NUM_PORTS  
    read -p "Enter starting port: " START_PORT  

    # Calculate ending port
    END_PORT=$((START_PORT + NUM_PORTS - 1))

    cat > $INSTALL_DIR/frpc.ini <<EOF
[common]
server_addr = $SERVER_IP
server_port = $SERVER_PORT
token = $TOKEN
EOF

    # Add SSH port first
    cat >> $INSTALL_DIR/frpc.ini <<EOF

[ssh$START_PORT]
type = tcp
local_ip = 127.0.0.1
local_port = 22
remote_port = $START_PORT
EOF

    # Add TCP ports
    CURRENT_PORT=$((START_PORT + 1))
    for ((i=2; i<=NUM_PORTS; i++)); do
        cat >> $INSTALL_DIR/frpc.ini <<EOF

[tcp$CURRENT_PORT]
type = tcp
local_ip = 127.0.0.1
local_port = $CURRENT_PORT
remote_port = $CURRENT_PORT
EOF
        CURRENT_PORT=$((CURRENT_PORT + 1))
    done

    cat > $SYSTEMD_DIR/frpc.service <<EOF
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
    read -p "Enter token: " TOKEN  

    cat > $INSTALL_DIR/frps.ini <<EOF
[common]
bind_port = $BIND_PORT
token = $TOKEN
EOF

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
    1) install_frpc ;;
    2) uninstall_frpc ;;
    3) install_frps ;;
    4) uninstall_frps ;;
    *) echo "Invalid option"; exit 1 ;;
esac    if [[ "$arch" == "unsupported" ]]; then
        echo "Unsupported architecture: $(uname -m)" >&2
        exit 1
    fi

    # Install dependencies
    apt-get update -y
    apt-get install -y wget tar

    # Download FRP
    echo "Downloading FRP..."
    wget -q "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${arch}.tar.gz" -O /tmp/frp.tar.gz
    mkdir -p "$INSTALL_DIR"
    tar -xzf /tmp/frp.tar.gz -C /tmp/
    cp /tmp/frp_${FRP_VERSION}_linux_${arch}/frp* "$INSTALL_DIR/" 2>/dev/null || true
    rm -rf /tmp/frp.tar.gz /tmp/frp_${FRP_VERSION}_linux_${arch}

    # Basic config
    echo
    echo "Basic Configuration:"
    read -p "FRPS server IP: " SERVER_IP
    read -p "FRPS server port [7000]: " SERVER_PORT
    SERVER_PORT=${SERVER_PORT:-7000}
    read -s -p "Token: " TOKEN
    echo

    # Create basic config
    cat > "$INSTALL_DIR/frpc.ini" << EOF
[common]
server_addr = $SERVER_IP
server_port = $SERVER_PORT
token = $TOKEN
EOF

    # SSH Port
    echo
    echo "SSH Port Configuration:"
    read -p "Enable SSH? [Y/n]: " ENABLE_SSH
    ENABLE_SSH=${ENABLE_SSH:-Y}
    if [[ "$ENABLE_SSH" =~ ^[Yy]$ ]]; then
        read -p "Local SSH port [22]: " LOCAL_SSH
        LOCAL_SSH=${LOCAL_SSH:-22}
        read -p "Remote SSH port [6000]: " REMOTE_SSH
        REMOTE_SSH=${REMOTE_SSH:-6000}
        
        cat >> "$INSTALL_DIR/frpc.ini" << EOF

[ssh]
type = tcp
local_ip = 127.0.0.1
local_port = $LOCAL_SSH
remote_port = $REMOTE_SSH
EOF
    fi

    # TCP Port Ranges
    echo
    echo "TCP Port Ranges:"
    read -p "How many port ranges do you want to add? " RANGE_COUNT
    
    for ((i=1; i<=RANGE_COUNT; i++)); do
        echo
        echo "Port Range $i:"
        read -p "Starting local port: " START_LOCAL
        read -p "Ending local port: " END_LOCAL
        read -p "Starting remote port: " START_REMOTE
        read -p "Ending remote port: " END_REMOTE
        read -p "Range name: " RANGE_NAME
        
        local count=$((END_LOCAL - START_LOCAL))
        local remote_count=$((END_REMOTE - START_REMOTE))
        
        if [[ $count -ne $remote_count ]]; then
            echo "Error: Local and remote range must have same number of ports!"
            continue
        fi
        
        for ((j=0; j<=count; j++)); do
            local_port=$((START_LOCAL + j))
            remote_port=$((START_REMOTE + j))
            cat >> "$INSTALL_DIR/frpc.ini" << EOF

[${RANGE_NAME}_${local_port}]
type = tcp
local_ip = 127.0.0.1
local_port = $local_port
remote_port = $remote_port
EOF
        done
        echo "Added $((count + 1)) ports: $START_LOCAL-$END_LOCAL → $START_REMOTE-$END_REMOTE"
    done

    # Create service
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
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    # Start service
    chmod +x "$INSTALL_DIR/frpc"
    systemctl daemon-reload
    systemctl enable frpc
    systemctl start frpc

    sleep 2
    if systemctl is-active --quiet frpc; then
        echo
        echo "FRPC installed successfully!"
        echo "Config: $INSTALL_DIR/frpc.ini"
        systemctl status frpc --no-pager
    else
        echo "FRPC failed to start. Check: journalctl -u frpc"
        exit 1
    fi
}

# Function to uninstall FRPC
uninstall_frpc() {
    echo "Uninstalling FRPC..."
    systemctl stop frpc 2>/dev/null || true
    systemctl disable frpc 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/frpc.service"
    rm -rf "$INSTALL_DIR"
    systemctl daemon-reload
    echo "FRPC uninstalled."
}

# Function to install FRPS
install_frps() {
    echo "Installing FRP Server..."
    
    if [[ -f "$SYSTEMD_DIR/frps.service" ]]; then
        echo "FRPS already installed. Uninstall first." >&2
        exit 1
    fi

    local arch
    arch=$(detect_arch)
    if [[ "$arch" == "unsupported" ]]; then
        echo "Unsupported architecture: $(uname -m)" >&2
        exit 1
    fi

    # Install dependencies
    apt-get update -y
    apt-get install -y wget tar

    # Download FRP
    echo "Downloading FRP..."
    wget -q "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${arch}.tar.gz" -O /tmp/frp.tar.gz
    mkdir -p "$INSTALL_DIR"
    tar -xzf /tmp/frp.tar.gz -C /tmp/
    cp /tmp/frp_${FRP_VERSION}_linux_${arch}/frp* "$INSTALL_DIR/" 2>/dev/null || true
    rm -rf /tmp/frp.tar.gz /tmp/frp_${FRP_VERSION}_linux_${arch}

    # Basic config
    echo
    echo "FRPS Configuration:"
    read -p "Bind port [7000]: " BIND_PORT
    BIND_PORT=${BIND_PORT:-7000}
    read -s -p "Token: " TOKEN
    echo

    # Create config
    cat > "$INSTALL_DIR/frps.ini" << EOF
[common]
bind_port = $BIND_PORT
token = $TOKEN
EOF

    # Create service
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
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    # Start service
    chmod +x "$INSTALL_DIR/frps"
    systemctl daemon-reload
    systemctl enable frps
    systemctl start frps

    sleep 2
    if systemctl is-active --quiet frps; then
        echo
        echo "FRPS installed successfully!"
        echo "Bind Port: $BIND_PORT"
        systemctl status frps --no-pager
    else
        echo "FRPS failed to start. Check: journalctl -u frps"
        exit 1
    fi
}

# Function to uninstall FRPS
uninstall_frps() {
    echo "Uninstalling FRPS..."
    systemctl stop frps 2>/dev/null || true
    systemctl disable frps 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/frps.service"
    rm -rf "$INSTALL_DIR"
    systemctl daemon-reload
    echo "FRPS uninstalled."
}

# Main menu
echo "=== FRP Installer ==="
echo "1) Install FRPC (Client)"
echo "2) Uninstall FRPC (Client)"
echo "3) Install FRPS (Server)"
echo "4) Uninstall FRPS (Server)"
read -p "Choose [1-4]: " OPTION

case $OPTION in
    1) install_frpc ;;
    2) uninstall_frpc ;;
    3) install_frps ;;
    4) uninstall_frps ;;
    *) echo "Invalid option"; exit 1 ;;
esac
