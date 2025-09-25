#!/bin/bash
set -e

FRP_VERSION="0.63.0"
INSTALL_DIR="/opt/frp"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_FILE="$SYSTEMD_DIR/frp.service"

echo "=== FRPC Auto Installer / Uninstaller ==="
echo "1) Install FRPC"
echo "2) Uninstall FRPC"
read -p "Choose an option [1/2]: " OPTION

if [[ "$OPTION" == "2" ]]; then
    echo ">>> Stopping FRPC service..."
    systemctl stop frp 2>/dev/null || true
    systemctl disable frp 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    rm -rf "$INSTALL_DIR"
    systemctl daemon-reload
    echo ">>> FRPC fully removed."
    exit 0
fi

# ========== INSTALL MODE ==========
echo ">>> Installing FRPC..."

# Install dependencies
apt-get update -y
apt-get install -y wget tar

# Download FRP
wget -q https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_amd64.tar.gz
mkdir -p $INSTALL_DIR
tar -zxvf frp_${FRP_VERSION}_linux_amd64.tar.gz -C $INSTALL_DIR --strip-components=1
rm -f frp_${FRP_VERSION}_linux_amd64.tar.gz

echo "FRPC installed to $INSTALL_DIR"

# Fixed server values
SERVER_IP="in-1.hectorhosting.xyz"
TOKEN="HyCR@Ansh@2k25"

# Ask for port details
read -p "How many ports do you want to forward? " NUM_PORTS
read -p "Enter starting port: " START_PORT
read -p "Enter ending port: " END_PORT

# Create frpc.ini
cat > $INSTALL_DIR/frpc.ini <<EOF
[common]
server_addr = $SERVER_IP
server_port = 7000
token = $TOKEN
EOF

# First entry: SSH (local 22 -> remote START_PORT)
cat >> $INSTALL_DIR/frpc.ini <<EOL

[ssh$START_PORT]
type = tcp
local_ip = 127.0.0.1
local_port = 22
remote_port = $START_PORT
EOL

# Generate the rest of the ports
CUR_PORT=$((START_PORT + 1))
i=2
while [[ $CUR_PORT -le $END_PORT && $i -le $NUM_PORTS ]]; do
cat >> $INSTALL_DIR/frpc.ini <<EOL

[tcp$CUR_PORT]
type = tcp
local_ip = 127.0.0.1
local_port = $CUR_PORT
remote_port = $CUR_PORT
EOL
    CUR_PORT=$((CUR_PORT + 1))
    i=$((i + 1))
done

# Create systemd service
cat > $SERVICE_FILE <<EOF
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

# Enable and start service
systemctl daemon-reload
systemctl enable frp
systemctl restart frp

echo "=== FRPC Setup Complete ==="
systemctl status frp --no-pager
