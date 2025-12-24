#!/bin/bash
CONF_FILE="/containers/smart-dns/nginx-sni.conf"
LOG_FILE="/containers/smart-dns/logs/google-ip-update.log"
SCRIPTS_DIR="/containers/smart-dns/scripts"

mkdir -p "$(dirname "$LOG_FILE")"
cd /containers/smart-dns

OLD_IP=$(grep -oP 'server \K[0-9.]+(?=:443)' "$CONF_FILE" | head -1)
NEW_IP=$(dig +short google.com | head -1)

echo "$(date): Old IP: $OLD_IP, New IP: $NEW_IP" >> "$LOG_FILE"

if [ "$OLD_IP" = "$NEW_IP" ] || [ -z "$NEW_IP" ]; then
    echo "$(date): No update needed" >> "$LOG_FILE"
    exit 0
fi

sed -i "s/server ${OLD_IP}:443;/server ${NEW_IP}:443;/g" "$CONF_FILE"
docker compose exec sni-proxy nginx -s reload

echo "$(date): Updated from $OLD_IP to $NEW_IP" >> "$LOG_FILE"

