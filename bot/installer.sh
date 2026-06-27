#!/bin/bash
# =================================================================
#  ChengetAI Deploy — DSpace 7.6 Non-Interactive Installer
#  Called by commander.py with environment variables set.
#
#  Environment variables:
#    DOMAIN       Domain or IP to serve DSpace on (default: localhost)
#    ADMIN_EMAIL  DSpace admin email
#    ADMIN_PASS   DSpace admin password
#    SSL_ENABLED  true | false (default: false)
#    DB_PASS      Postgres password (auto-generated if not set)
#
#  Manual test:
#    DOMAIN=library.example.com SSL_ENABLED=true bash bot/installer.sh
# =================================================================
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Variables ────────────────────────────────────────────────────
DOMAIN="${DOMAIN:-localhost}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@${DOMAIN}}"
ADMIN_PASS="${ADMIN_PASS:-ChengetAI2026!}"
SSL_ENABLED="${SSL_ENABLED:-false}"
DB_PASS="${DB_PASS:-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)}"
DIR="/opt/dspace"
IMAGES_TAG="dspace-7.6.3"

# Protocol for DSpace URLs
[ "$SSL_ENABLED" = "true" ] && PROTO="https" || PROTO="http"
BASE_URL="${PROTO}://${DOMAIN}"

# ── Logging ──────────────────────────────────────────────────────
log() { echo "[$(date '+%H:%M:%S')] $*"; }
ok()  { echo "[$(date '+%H:%M:%S')] ✓ $*"; }
err() { echo "[$(date '+%H:%M:%S')] ✗ $*" >&2; exit 1; }

echo "=================================================="
echo "  ChengetAI Deploy — DSpace 7.6"
echo "  Domain:  $DOMAIN"
echo "  SSL:     $SSL_ENABLED"
echo "  URL:     $BASE_URL"
echo "=================================================="

# ── 1. Docker ────────────────────────────────────────────────────
log "Checking Docker..."
if ! command -v docker &>/dev/null; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh -s -- --quiet
    systemctl enable --now docker
fi
if ! docker compose version &>/dev/null 2>&1; then
    apt-get install -y -qq docker-compose-plugin
fi
ok "Docker ready"

# ── 2. Free port 80 ──────────────────────────────────────────────
log "Freeing port 80..."
systemctl stop nginx 2>/dev/null || true
systemctl disable nginx 2>/dev/null || true
fuser -k 80/tcp 2>/dev/null || true
ok "Port 80 free"

# ── 3. Write config ───────────────────────────────────────────────
log "Writing configuration to $DIR..."
mkdir -p "$DIR/config/branding"
cd "$DIR"

# ── docker-compose.yml ───────────────────────────────────────────
cat > docker-compose.yml << COMPOSE
version: '3.8'
networks:
  dspace:
    driver: bridge
volumes:
  pgdata:
  solrdata:
  assetstore:
services:

  postgres:
    image: dspace/dspace-postgres-pgcrypto:${IMAGES_TAG}
    container_name: dspace-db
    restart: unless-stopped
    networks: [dspace]
    environment:
      POSTGRES_DB: dspace
      POSTGRES_USER: dspace
      POSTGRES_PASSWORD: "${DB_PASS}"
    volumes: [pgdata:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dspace -d dspace"]
      interval: 10s
      timeout: 5s
      retries: 10

  solr:
    image: dspace/dspace-solr:${IMAGES_TAG}
    container_name: dspace-solr
    restart: unless-stopped
    networks: [dspace]
    volumes: [solrdata:/var/solr]
    command: >
      bash -c "
        precreate-core search     /opt/solr/server/solr/search     2>/dev/null || true
        precreate-core statistics /opt/solr/server/solr/statistics 2>/dev/null || true
        precreate-core authority  /opt/solr/server/solr/authority  2>/dev/null || true
        precreate-core oai        /opt/solr/server/solr/oai        2>/dev/null || true
        exec solr-foreground
      "
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8983/solr/"]
      interval: 15s
      timeout: 10s
      retries: 15
      start_period: 30s

  dspace:
    image: dspace/dspace:${IMAGES_TAG}
    container_name: dspace-backend
    restart: unless-stopped
    networks: [dspace]
    depends_on:
      postgres: {condition: service_healthy}
      solr:     {condition: service_healthy}
    environment:
      db__P__url:             "jdbc:postgresql://postgres:5432/dspace"
      db__P__username:        dspace
      db__P__password:        "${DB_PASS}"
      solr__P__server:        "http://solr:8983/solr"
      dspace__P__server__url: "${BASE_URL}/server"
      dspace__P__ui__url:     "${BASE_URL}"
      dspace__P__name:        "Institutional Repository"
      dspace__P__hostname:    "${DOMAIN}"
      mail__P__from__address: "dspace@${DOMAIN}"
      mail__P__admin:         "${ADMIN_EMAIL}"
    volumes: [assetstore:/dspace/assetstore]
    ports: ["127.0.0.1:8080:8080"]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/server/api"]
      interval: 30s
      timeout: 15s
      retries: 20
      start_period: 180s

  dspace-ui:
    image: dspace/dspace-angular:${IMAGES_TAG}-dist
    container_name: dspace-frontend
    restart: unless-stopped
    networks: [dspace]
    depends_on:
      dspace: {condition: service_healthy}
    environment:
      DSPACE_UI_SSL:         "${SSL_ENABLED}"
      DSPACE_UI_HOST:        "${DOMAIN}"
      DSPACE_UI_PORT:        "4000"
      DSPACE_UI_NAMESPACE:   "/"
      DSPACE_REST_SSL:       "${SSL_ENABLED}"
      DSPACE_REST_HOST:      "${DOMAIN}"
      DSPACE_REST_PORT:      "$([ "$SSL_ENABLED" = "true" ] && echo 443 || echo 80)"
      DSPACE_REST_NAMESPACE: "/server"
    ports: ["127.0.0.1:4000:4000"]

  nginx:
    image: nginx:alpine
    container_name: dspace-nginx
    restart: unless-stopped
    networks: [dspace]
    depends_on: [dspace, dspace-ui]
    volumes:
      - ./config/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
    ports:
      - "80:80"
      - "443:443"
COMPOSE

ok "docker-compose.yml written"

# ── nginx.conf (HTTP or HTTPS) ───────────────────────────────────
if [ "$SSL_ENABLED" = "true" ]; then
    cat > config/nginx.conf << NGINX
upstream dspace_backend  { server dspace-backend:8080;  keepalive 16; }
upstream dspace_frontend { server dspace-frontend:4000; keepalive 16; }

# Redirect HTTP → HTTPS
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};
    client_max_body_size 512M;

    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location /server {
        proxy_pass         http://dspace_backend;
        proxy_set_header   Host            \$host;
        proxy_set_header   X-Real-IP       \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_read_timeout 300s;
    }

    location / {
        proxy_pass         http://dspace_frontend;
        proxy_set_header   Host            \$host;
        proxy_set_header   X-Real-IP       \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade         \$http_upgrade;
        proxy_set_header   Connection      "upgrade";
        proxy_read_timeout 300s;
    }
}
NGINX
else
    cat > config/nginx.conf << 'NGINX'
upstream dspace_backend  { server dspace-backend:8080;  keepalive 16; }
upstream dspace_frontend { server dspace-frontend:4000; keepalive 16; }

server {
    listen 80;
    server_name _;
    client_max_body_size 512M;

    location /server {
        proxy_pass         http://dspace_backend;
        proxy_set_header   Host            $host;
        proxy_set_header   X-Real-IP       $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_set_header   Connection "";
        proxy_read_timeout 300s;
    }

    location / {
        proxy_pass         http://dspace_frontend;
        proxy_set_header   Host            $host;
        proxy_set_header   X-Real-IP       $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade         $http_upgrade;
        proxy_set_header   Connection      "upgrade";
        proxy_read_timeout 300s;
    }
}
NGINX
fi
ok "nginx.conf written (SSL=$SSL_ENABLED)"

# ── 4. SSL Certificate ───────────────────────────────────────────
if [ "$SSL_ENABLED" = "true" ]; then
    log "Obtaining SSL certificate for $DOMAIN..."
    apt-get install -y -qq certbot

    # Stop nginx container to free port 80 for standalone challenge
    docker stop dspace-nginx 2>/dev/null || true

    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$ADMIN_EMAIL" \
        -d "$DOMAIN" \
        || err "Certbot failed — is DNS for $DOMAIN pointing to this server?"

    ok "SSL certificate obtained"
fi

# ── 5. Start containers ───────────────────────────────────────────
log "Pulling images (may take several minutes)..."
docker compose down --remove-orphans 2>/dev/null || true
docker compose pull
docker compose up -d
ok "Containers started"

# ── 6. Wait for backend ───────────────────────────────────────────
log "Waiting for DSpace backend (4-6 min)..."
ELAPSED=0
until curl -sf --connect-timeout 5 http://localhost:8080/server/api &>/dev/null; do
    echo -n "."
    sleep 10
    ELAPSED=$((ELAPSED+10))
    [ $ELAPSED -ge 660 ] && err "Backend timeout after 11 min. Run: docker logs dspace-backend"
done
ok "Backend ready (${ELAPSED}s)"

log "Waiting for Angular UI..."
ELAPSED=0
until curl -sf --connect-timeout 5 http://localhost:4000/ &>/dev/null; do
    echo -n "."
    sleep 10
    ELAPSED=$((ELAPSED+10))
    [ $ELAPSED -ge 360 ] && err "Frontend timeout. Run: docker logs dspace-frontend"
done
ok "UI ready"

# ── 7. Create admin account ───────────────────────────────────────
log "Creating admin account..."
docker exec dspace-backend /dspace/bin/dspace create-administrator \
    -e "$ADMIN_EMAIL" \
    -f "ChengetAI" \
    -l "Admin" \
    -p "$ADMIN_PASS" \
    -c "en" 2>&1 | grep -Ev "^$|log4j" || true
ok "Admin account created: $ADMIN_EMAIL"

# ── Done ─────────────────────────────────────────────────────────
echo ""
echo "=================================================="
echo "  DEPLOYMENT COMPLETE"
echo "  URL:    $BASE_URL/"
echo "  Login:  $ADMIN_EMAIL"
echo "  Pass:   $ADMIN_PASS"
echo "=================================================="
