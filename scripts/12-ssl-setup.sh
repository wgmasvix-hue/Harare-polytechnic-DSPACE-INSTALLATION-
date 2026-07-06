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
die()  { echo -e "${YELLOW}[ERROR]${NC} $1"; exit 1; }

DEFAULT_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
SERVER_HOST="${DSPACE_HOSTNAME:-${DEFAULT_HOST:-localhost}}"
SERVER_NAME="${DSPACE_SERVER_NAME:-repository-host}"
ADMIN_EMAIL="${DSPACE_ADMIN_EMAIL:-admin@example.edu}"
CERT_DIR="/etc/ssl/dspace"
NGINX_CONF="/etc/nginx/sites-available/dspace"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

# Docker mode — adjust nginx config path
if docker ps 2>/dev/null | grep -q dspace-nginx; then
    NGINX_MODE="docker"
else
    NGINX_MODE="native"
fi

if [ -f "${ENV_FILE}" ]; then
    # shellcheck disable=SC1091
    source "${ENV_FILE}"
    SERVER_HOST="${SERVER_HOST:-${DEFAULT_HOST:-localhost}}"
    SERVER_NAME="${SERVER_NAME:-repository-host}"
    ADMIN_EMAIL="${DSPACE_ADMIN_EMAIL:-${ADMIN_EMAIL}}"
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
    SSL_CERT_FILE="${CERT_DIR}/dspace.crt"
    SSL_KEY_FILE="${CERT_DIR}/dspace.key"
    ;;

2)
    # ---- Let's Encrypt ----
    DOMAIN="${1:-}"
    [ -z "$DOMAIN" ] && read -rp "Your public domain name (e.g. repo.example.edu): " DOMAIN

    log "Installing Certbot..."
    apt-get install -y certbot python3-certbot-nginx 2>/dev/null || \
    dnf install -y certbot python3-certbot-nginx 2>/dev/null || \
    die "Could not install certbot"

    if [ "$NGINX_MODE" = "docker" ]; then
        log "Stopping docker nginx temporarily for ACME challenge..."
        docker stop dspace-nginx >/dev/null
        trap 'docker start dspace-nginx >/dev/null 2>&1 || true' EXIT

        log "Requesting certificate for ${DOMAIN}..."
        certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos \
            -m "${ADMIN_EMAIL}"

        mkdir -p /etc/letsencrypt/renewal-hooks/pre /etc/letsencrypt/renewal-hooks/post
        cat > /etc/letsencrypt/renewal-hooks/pre/10-dspace-nginx-stop.sh <<'HOOKPRE'
#!/bin/sh
docker stop dspace-nginx >/dev/null 2>&1 || true
HOOKPRE
        cat > /etc/letsencrypt/renewal-hooks/post/10-dspace-nginx-start.sh <<'HOOKPOST'
#!/bin/sh
docker start dspace-nginx >/dev/null 2>&1 || true
HOOKPOST
        chmod +x /etc/letsencrypt/renewal-hooks/pre/10-dspace-nginx-stop.sh /etc/letsencrypt/renewal-hooks/post/10-dspace-nginx-start.sh
        ok "Let's Encrypt certificate installed with docker renewal hooks"
    else
        log "Requesting certificate for ${DOMAIN}..."
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos \
            -m "${ADMIN_EMAIL}" --redirect
        ok "Let's Encrypt certificate installed"
    fi

    systemctl enable certbot.timer 2>/dev/null || \
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
    ok "Certbot auto-renewal enabled"

    CERT_DIR="/etc/letsencrypt/live/${DOMAIN}"
    SSL_CERT_FILE="${CERT_DIR}/fullchain.pem"
    SSL_KEY_FILE="${CERT_DIR}/privkey.pem"
    ;;
*)
    echo "Invalid option."; exit 1 ;;
esac

# ---- Update Nginx config for HTTPS ----
log "Updating Nginx configuration for HTTPS..."

if [ "$NGINX_MODE" = "docker" ]; then
    NGINX_CONF="${REPO_ROOT}/config/nginx.conf"
    BACKEND_UPSTREAM="http://dspace:8080"
    FRONTEND_UPSTREAM="http://dspace-ui:4000"
else
    BACKEND_UPSTREAM="http://127.0.0.1:8080"
    FRONTEND_UPSTREAM="http://127.0.0.1:4000"
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
    ssl_certificate     ${SSL_CERT_FILE};
    ssl_certificate_key ${SSL_KEY_FILE};

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
        proxy_pass ${BACKEND_UPSTREAM};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 300s;
    }

    # DSpace Angular UI
    location / {
        proxy_pass ${FRONTEND_UPSTREAM};
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

if [ -f "${ENV_FILE}" ]; then
    grep -q '^PUBLIC_PROTOCOL=' "${ENV_FILE}" || echo 'PUBLIC_PROTOCOL=http' >> "${ENV_FILE}"
    grep -q '^DSPACE_UI_SSL=' "${ENV_FILE}" || echo 'DSPACE_UI_SSL=false' >> "${ENV_FILE}"
    grep -q '^DSPACE_REST_SSL=' "${ENV_FILE}" || echo 'DSPACE_REST_SSL=false' >> "${ENV_FILE}"
    grep -q '^DSPACE_REST_PORT=' "${ENV_FILE}" || echo 'DSPACE_REST_PORT=80' >> "${ENV_FILE}"
    sed -i "s|^SERVER_HOST=.*|SERVER_HOST=${SERVER_HOST}|" "${ENV_FILE}"
    sed -i "s|^PUBLIC_PROTOCOL=.*|PUBLIC_PROTOCOL=https|" "${ENV_FILE}"
    sed -i "s|^DSPACE_UI_SSL=.*|DSPACE_UI_SSL=true|" "${ENV_FILE}"
    sed -i "s|^DSPACE_REST_SSL=.*|DSPACE_REST_SSL=true|" "${ENV_FILE}"
    sed -i "s|^DSPACE_REST_PORT=.*|DSPACE_REST_PORT=443|" "${ENV_FILE}"
fi

if [ -f "${REPO_ROOT}/config/local.cfg" ]; then
    sed -i "s|^dspace\\.hostname = .*|dspace.hostname = ${SERVER_HOST}|" "${REPO_ROOT}/config/local.cfg"
    sed -i "s|^dspace\\.server\\.url = .*|dspace.server.url = https://${SERVER_HOST}/server|" "${REPO_ROOT}/config/local.cfg"
    sed -i "s|^dspace\\.ui\\.url = .*|dspace.ui.url = https://${SERVER_HOST}|" "${REPO_ROOT}/config/local.cfg"
    sed -i "s|^oai\\.url = .*|oai.url = https://${SERVER_HOST}/server/oai/request|" "${REPO_ROOT}/config/local.cfg"
fi

# Reload nginx
if [ "$NGINX_MODE" = "docker" ]; then
    docker compose -f "${REPO_ROOT}/docker-compose.yml" restart nginx
    docker compose -f "${REPO_ROOT}/docker-compose.yml" up -d dspace dspace-ui
    trap - EXIT
else
    nginx -t && systemctl reload nginx
fi

ok "HTTPS configured"
echo ""
echo "DSpace URLs updated to HTTPS."
echo "Restart services if needed: make restart"
