#!/bin/bash
# =================================================================
#  SSL/HTTPS Setup for DSpace
#  Option A: Self-signed certificate (works on LAN immediately)
#  Option B: Let's Encrypt (requires public domain name)
# =================================================================

set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${BLUE}==>${NC} $1"; }
ok()   { echo -e "${GREEN}[DONE]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

DEFAULT_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
SERVER_HOST="${DSPACE_HOSTNAME:-${DEFAULT_HOST:-localhost}}"
SERVER_NAME="${DSPACE_SERVER_NAME:-repository-host}"
ADMIN_EMAIL="${DSPACE_ADMIN_EMAIL:-admin@example.edu}"
CERT_DIR="/etc/ssl/dspace"
NGINX_CONF="/etc/nginx/sites-available/dspace"

# Docker mode — adjust nginx config path
if docker ps 2>/dev/null | grep -q dspace-nginx; then
    NGINX_MODE="docker"
else
    NGINX_MODE="native"
fi

mkdir -p "$CERT_DIR"

echo ""
echo "SSL Setup Options:"
echo "  1) Self-signed certificate (LAN/intranet — immediate)"
echo "  2) Let's Encrypt (requires public domain + internet access)"
echo ""
read -rp "Choose [1/2]: " SSL_OPTION

case "$SSL_OPTION" in
1)
    # ---- Self-Signed Certificate ----
    log "Generating self-signed certificate for ${SERVER_HOST}..."
    if [[ "$SERVER_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        SUBJECT_ALT_NAME="IP:${SERVER_HOST},DNS:${SERVER_NAME}"
    else
        SUBJECT_ALT_NAME="DNS:${SERVER_HOST},DNS:${SERVER_NAME}"
    fi

    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "${CERT_DIR}/dspace.key" \
        -out    "${CERT_DIR}/dspace.crt" \
        -subj "/C=ZW/ST=Harare/L=Harare/O=Harare Polytechnic/OU=Repository/CN=${SERVER_HOST}" \
        -extensions v3_ca \
        -addext "subjectAltName=${SUBJECT_ALT_NAME}"

    ok "Self-signed certificate generated (valid 10 years)"
    warn "Browsers will show a security warning — click 'Advanced > Proceed'"
    warn "To avoid warnings: import ${CERT_DIR}/dspace.crt into Windows Certificate Store"
    ;;

2)
    # ---- Let's Encrypt ----
    DOMAIN="${1:-}"
    [ -z "$DOMAIN" ] && read -rp "Your public domain name (e.g. repo.example.edu): " DOMAIN

    log "Installing Certbot..."
    apt-get install -y certbot python3-certbot-nginx 2>/dev/null || \
    dnf install -y certbot python3-certbot-nginx 2>/dev/null

    log "Requesting certificate for ${DOMAIN}..."
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos \
        -m "${ADMIN_EMAIL}" --redirect

    # Auto-renewal
    systemctl enable certbot.timer 2>/dev/null || \
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
    ok "Let's Encrypt certificate installed with auto-renewal"

    CERT_DIR="/etc/letsencrypt/live/${DOMAIN}"
    ;;
*)
    echo "Invalid option."; exit 1 ;;
esac

# ---- Update Nginx config for HTTPS ----
log "Updating Nginx configuration for HTTPS..."

if [ "$NGINX_MODE" = "docker" ]; then
    NGINX_CONF="$(dirname $0)/../config/nginx.conf"
fi

cat > "${NGINX_CONF}" <<NGINXSSL
# Harare Polytechnic DSpace — Nginx HTTPS Configuration

# Redirect HTTP → HTTPS
server {
    listen 80;
    server_name ${SERVER_HOST} ${SERVER_NAME} _;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name ${SERVER_HOST} ${SERVER_NAME} _;

    # SSL certificates
    ssl_certificate     ${CERT_DIR}/dspace.crt;
    ssl_certificate_key ${CERT_DIR}/dspace.key;

    # Modern SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    # HSTS (uncomment after confirming HTTPS works)
    # add_header Strict-Transport-Security "max-age=63072000" always;

    client_max_body_size 512M;
    client_body_timeout 300s;

    # DSpace REST API
    location /server {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 300s;
    }

    # DSpace Angular UI
    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 300s;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
}
NGINXSSL

# Reload nginx
if [ "$NGINX_MODE" = "docker" ]; then
    docker exec dspace-nginx nginx -s reload 2>/dev/null || true
    warn "Restart the nginx container to apply SSL: docker compose restart nginx"
else
    nginx -t && systemctl reload nginx
fi

ok "HTTPS configured"
echo ""
echo "Update DSpace URLs from http:// to https:// in:"
echo "  /dspace/config/local.cfg  (or config/local.cfg)"
echo "  Change: dspace.server.url = https://${SERVER_HOST}/server"
echo "  Change: dspace.ui.url     = https://${SERVER_HOST}"
echo ""
echo "Then restart DSpace: make restart"
