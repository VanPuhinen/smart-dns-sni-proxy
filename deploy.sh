#!/bin/bash
# Smart DNS & SNI Proxy - One-line deployment script
# Usage: curl -sL https://raw.githubusercontent.com/VanPuhinen/smart-dns-sni-proxy/main/deploy.sh | bash

set -e

NEW_IP=$(hostname -I | awk '{print $1}')
REPO_URL="https://github.com/VanPuhinen/smart-dns-sni-proxy.git"

echo "=== Deploying Smart DNS & SNI Proxy on $NEW_IP ==="

# 0. CRITICAL: Force system DNS before anything else
echo "[1/10] Configuring system DNS..."
sudo rm -f /etc/resolv.conf
sudo sh -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
sudo sh -c 'echo "nameserver 1.1.1.1" >> /etc/resolv.conf'
sudo chattr +i /etc/resolv.conf 2>/dev/null || true

# 1. Install essentials
echo "[2/10] Installing Docker, Docker Compose v2 and Git..."
sudo apt update
sudo apt install -y docker.io git curl

# Install Docker Compose v2
echo "[3/10] Installing Docker Compose v2..."
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# 2. Configure Docker DNS BEFORE any Docker operations
echo "[4/10] Configuring Docker DNS..."
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "dns": ["8.8.8.8", "1.1.1.1"],
  "dns-opts": ["attempts:3", "timeout:3"]
}
EOF

# 3. Restart Docker with new config
echo "[5/10] Restarting Docker service..."
sudo systemctl daemon-reload
sudo systemctl restart docker
sleep 3  # Wait for Docker to fully restart

# 4. Verify Docker DNS works
echo "[6/10] Verifying Docker network..."
sudo docker run --rm alpine nslookup google.com 2>&1 | grep -q "Address" && echo "✓ Docker DNS working" || echo "⚠ Docker DNS check failed"

# 5. Clone and configure
echo "[7/10] Cloning repository..."
git clone $REPO_URL
cd smart-dns-sni-proxy

echo "[8/10] Configuring for IP $NEW_IP..."
cp .env.example .env
sed -i "s/YOUR_SERVER_IP/$NEW_IP/g" .env

mkdir -p adguard-data/conf
cp config-examples/AdGuardHome.yaml.example adguard-data/conf/AdGuardHome.yaml
sed -i "s/YOUR_SERVER_IP/$NEW_IP/g" adguard-data/conf/AdGuardHome.yaml

# 6. Stop systemd-resolved (if running)
echo "[9/10] Stopping systemd-resolved..."
sudo systemctl stop systemd-resolved 2>/dev/null || true
sudo systemctl disable systemd-resolved 2>/dev/null || true
sudo systemctl mask systemd-resolved 2>/dev/null || true

# 7. Fix docker-compose.yml
echo "[10/10] Creating docker-compose.yml and starting containers..."
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

# Start everything
sudo docker-compose up -d

# Wait for containers to initialize
sleep 5

echo ""
echo "=== DEPLOYMENT COMPLETE! ==="
echo "✓ Services deployed"
echo "✓ AdGuard Web UI: http://$NEW_IP:3000"
echo "✓ Client DNS: $NEW_IP"
echo ""
echo "Quick tests:"
echo "1. DNS check:   nslookup google.com $NEW_IP"
echo "2. Port check:  sudo netstat -tulpn | grep -E ':(53|443)'"
echo "3. Containers:  sudo docker-compose ps"
echo ""
echo "NEXT STEPS:"
echo "1. Reconnect via SSH to apply docker group permissions"
echo "2. Open http://$NEW_IP:3000 and set AdGuard admin password"
echo "3. Test from client: curl -vk --resolve 'google.com:443:$NEW_IP' https://google.com"
echo ""
echo "Troubleshooting:"
echo "- If DNS fails: sudo systemctl restart docker && sudo docker-compose restart adguard"
echo "- If port 53 busy: sudo lsof -i :53"
