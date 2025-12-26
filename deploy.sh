#!/bin/bash
# Smart DNS & SNI Proxy - One-line deployment script
# Usage: curl -sL https://raw.githubusercontent.com/VanPuhinen/smart-dns-sni-proxy/main/deploy.sh | bash

set -e

NEW_IP=$(hostname -I | awk '{print $1}')
REPO_URL="https://github.com/VanPuhinen/smart-dns-sni-proxy.git"

echo "=== Deploying Smart DNS & SNI Proxy on $NEW_IP ==="

# 0. Temporary DNS fix
echo "[1/8] Configuring temporary DNS..."
sudo sh -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
sudo sh -c 'echo "nameserver 1.1.1.1" >> /etc/resolv.conf'

# 1. Install essentials
echo "[2/8] Installing Docker, Docker Compose v2 and Git..."
sudo apt update
sudo apt install -y docker.io git curl

# Install Docker Compose v2
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# 2. Configure Docker DNS (CRITICAL FIX)
echo "[3/8] Configuring Docker DNS..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF
sudo systemctl restart docker

# 3. Clone and configure
echo "[4/8] Cloning repository..."
git clone $REPO_URL
cd smart-dns-sni-proxy

echo "[5/8] Configuring for IP $NEW_IP..."
cp .env.example .env
sed -i "s/YOUR_SERVER_IP/$NEW_IP/g" .env

mkdir -p adguard-data/conf
cp config-examples/AdGuardHome.yaml.example adguard-data/conf/AdGuardHome.yaml
sed -i "s/YOUR_SERVER_IP/$NEW_IP/g" adguard-data/conf/AdGuardHome.yaml

# 4. Stop systemd-resolved
echo "[6/8] Stopping systemd-resolved..."
sudo systemctl stop systemd-resolved 2>/dev/null || true
sudo systemctl disable systemd-resolved 2>/dev/null || true

# 5. Fix docker-compose.yml (critical: expose port 53)
echo "[7/8] Creating docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
services:
  adguard:
    image: adguard/adguardhome:latest
    container_name: adguard
    restart: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "3000:3000/tcp"
    volumes:
      - ./adguard-data/conf:/opt/adguardhome/conf
      - ./adguard-data/work:/opt/adguardhome/work
    cap_add:
      - NET_ADMIN

  sni-proxy:
    image: nginx:latest
    container_name: sni-proxy
    restart: unless-stopped
    ports:
      - "443:8443/tcp"
    volumes:
      - ./nginx-sni.conf:/etc/nginx/nginx.conf:ro
    command: ["nginx", "-g", "daemon off;"]

  dot-proxy:
    image: nginx:latest
    container_name: dot-proxy
    restart: unless-stopped
    ports:
      - "853:853/tcp"
    volumes:
      - ./nginx-dot.conf:/etc/nginx/nginx.conf:ro
      - ./nginx-certs:/etc/ssl/private:ro
    command: ["nginx", "-g", "daemon off;"]
EOF

# 6. Start services
echo "[8/8] Starting containers..."
sudo docker-compose up -d

echo ""
echo "=== DEPLOYMENT COMPLETE! ==="
echo "AdGuard Web UI: http://$NEW_IP:3000"
echo "Client DNS: $NEW_IP"
echo ""
echo "Run these tests:"
echo "1. DNS: nslookup google.com $NEW_IP"
echo "2. SNI Proxy: curl -vk --resolve 'google.com:443:$NEW_IP' https://google.com"
echo ""
echo "IMPORTANT:"
echo "1. Reconnect via SSH to apply docker group permissions!"
echo "2. Setup AdGuard password at http://$NEW_IP:3000"