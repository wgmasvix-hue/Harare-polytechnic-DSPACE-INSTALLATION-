#!/bin/bash
# Step 7: Configure Nginx as reverse proxy for DSpace
# This makes DSpace accessible on port 80 (HTTP) instead of 8080/4000

set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
ok()  { echo -e "${GREEN}[OK]${NC} $1"; }

DEFAULT_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
SERVER_HOSTNAME="${DSPACE_HOSTNAME:-${DEFAULT_HOST:-localhost}}"
SERVER_NAME="${DSPACE_SERVER_NAME:-repository-host}"

log "Configuring Nginx reverse proxy..."

# Install nginx if needed
command -v nginx &>/dev/null || {
    apt-get install -y nginx 2>/dev/null || dnf install -y nginx 2>/dev/null
}

# Remove default site
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# DSpace nginx config
cat > /etc/nginx/sites-available/dspace <<NGINXCFG
# Harare Polytechnic DSpace - Nginx Reverse Proxy
server {
    listen 80;
    server_name ${SERVER_NAME} ${SERVER_HOSTNAME} _;

    client_max_body_size 512M;
    client_body_timeout 300s;

    # DSpace Angular UI (frontend)
    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }

    # DSpace REST API (backend)
    location /server {
        proxy_pass http://127.0.0.1:8080/server;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }

    # Solr admin (restrict in production - only allow from localhost/admin net)
    location /solr {
        allow 127.0.0.1;
        allow 192.168.26.0/24;
        deny all;
        proxy_pass http://127.0.0.1:8983/solr;
        proxy_set_header Host \$host;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
}
NGINXCFG

# Enable site
ln -sf /etc/nginx/sites-available/dspace /etc/nginx/sites-enabled/dspace 2>/dev/null || \
    cp /etc/nginx/sites-available/dspace /etc/nginx/conf.d/dspace.conf

# Test and reload nginx
nginx -t && systemctl reload nginx
systemctl enable nginx

ok "Nginx reverse proxy configured"
echo ""
echo "DSpace is now accessible at:"
echo "  http://${SERVER_HOSTNAME}       (main UI)"
echo "  http://${SERVER_NAME}           (if DNS/hosts resolves)"
echo "  http://${SERVER_HOSTNAME}/server (REST API)"
