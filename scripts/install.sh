#!/bin/bash
# =================================================================
#  DSpace 7.6 — Harare Polytechnic  (straight-forward installer)
#
#  Contabo VPS:
#    bash <(curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/harare-polytechnic-dspace-installation-/claude/dspace-harare-polytechnic-install-0asotw/scripts/install.sh)
#
#  Local server (set IP first):
#    SERVER_IP="192.168.26.3" bash <(curl -fsSL <same url>)
# =================================================================
set -e

# ── Variables (override from environment) ───────────────────────
SERVER_IP="${SERVER_IP:-$(curl -sf --connect-timeout 5 https://api.ipify.org || hostname -I | awk '{print $1}')}"
DB_PASS="${DB_PASS:-DSpaceHarare2024}"
ADMIN_EMAIL="${ADMIN_EMAIL:-library@hrepoly.ac.zw}"
ADMIN_PASS="${ADMIN_PASS:-AdminHarare2024}"
DIR="/opt/dspace"

echo ""
echo "========================================"
echo "  DSpace 7.6 — Harare Polytechnic"
echo "  Server: $SERVER_IP"
echo "========================================"

# ── 1. Docker ────────────────────────────────────────────────────
echo "[1/6] Installing Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh -s -- --quiet
    systemctl enable --now docker
fi
if ! docker compose version &>/dev/null 2>&1; then
    apt-get install -y -qq docker-compose-plugin 2>/dev/null || true
fi
echo "      Docker OK"

# ── 2. Free port 80 ──────────────────────────────────────────────
echo "[2/6] Freeing port 80..."
systemctl stop nginx  2>/dev/null || true
systemctl disable nginx 2>/dev/null || true
fuser -k 80/tcp 2>/dev/null || true
echo "      Port 80 free"

# ── 3. Write config files ────────────────────────────────────────
echo "[3/6] Writing configuration..."
mkdir -p "$DIR/config"
cd "$DIR"

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
    image: dspace/dspace-postgres-pgcrypto:dspace-7.6.3
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
    image: dspace/dspace-solr:dspace-7.6.3
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
    image: dspace/dspace:dspace-7.6.3
    container_name: dspace-backend
    restart: unless-stopped
    networks: [dspace]
    depends_on:
      postgres: {condition: service_healthy}
      solr:    {condition: service_healthy}
    environment:
      db__P__url:            "jdbc:postgresql://postgres:5432/dspace"
      db__P__username:       dspace
      db__P__password:       "${DB_PASS}"
      solr__P__server:       "http://solr:8983/solr"
      dspace__P__server__url: "http://${SERVER_IP}/server"
      dspace__P__ui__url:    "http://${SERVER_IP}"
      dspace__P__name:       "Harare Polytechnic Institutional Repository"
      dspace__P__hostname:   "${SERVER_IP}"
      mail__P__from__address: "dspace@hrepoly.ac.zw"
      mail__P__admin:         "library@hrepoly.ac.zw"
    volumes: [assetstore:/dspace/assetstore]
    ports: ["127.0.0.1:8080:8080"]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/server/api"]
      interval: 30s
      timeout: 15s
      retries: 20
      start_period: 180s

  dspace-ui:
    image: dspace/dspace-angular:dspace-7.6.3-dist
    container_name: dspace-frontend
    restart: unless-stopped
    networks: [dspace]
    depends_on:
      dspace: {condition: service_healthy}
    environment:
      DSPACE_UI_SSL: "false"
      DSPACE_UI_HOST: "${SERVER_IP}"
      DSPACE_UI_PORT: "4000"
      DSPACE_UI_NAMESPACE: "/"
      DSPACE_REST_SSL: "false"
      DSPACE_REST_HOST: "${SERVER_IP}"
      DSPACE_REST_PORT: "80"
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
    ports: ["80:80"]
COMPOSE

cat > config/nginx.conf << 'NGINX'
upstream dspace_backend  { server dspace-backend:8080;  keepalive 16; }
upstream dspace_frontend { server dspace-frontend:4000; keepalive 16; }

server {
    listen 80;
    server_name _;
    client_max_body_size 512M;

    location /server {
        proxy_pass         http://dspace_backend;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
        proxy_http_version 1.1;
        proxy_set_header   Connection "";
    }

    location / {
        proxy_pass         http://dspace_frontend;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade           $http_upgrade;
        proxy_set_header   Connection        "upgrade";
        proxy_read_timeout 300s;
    }
}
NGINX

echo "      Config files written"

# ── 4. Start containers ──────────────────────────────────────────
echo "[4/6] Starting DSpace containers..."
docker compose down --remove-orphans 2>/dev/null || true
docker compose pull
docker compose up -d

echo "      Waiting for DSpace backend (4-6 min)..."
printf "      "
SECS=0
until curl -sf --connect-timeout 5 http://localhost:8080/server/api &>/dev/null; do
    printf "."
    sleep 10
    SECS=$((SECS+10))
    [ $SECS -ge 600 ] && { echo ""; echo "ERROR: Backend not ready after 10 min."; echo "Check: docker logs dspace-backend"; exit 1; }
done
echo " backend ready!"

echo "      Waiting for Angular UI (1-2 more min)..."
printf "      "
SECS=0
until curl -sf --connect-timeout 5 http://localhost:4000/ &>/dev/null; do
    printf "."
    sleep 10
    SECS=$((SECS+10))
    [ $SECS -ge 300 ] && { echo ""; echo "ERROR: Frontend not ready after 5 min."; echo "Check: docker logs dspace-frontend"; exit 1; }
done
echo " UI ready!"

# ── 5. Create admin ──────────────────────────────────────────────
echo "[5/6] Creating admin account..."
docker exec dspace-backend /dspace/bin/dspace create-administrator \
    -e "$ADMIN_EMAIL" -f Library -l Admin -p "$ADMIN_PASS" -c en 2>&1 | grep -v "^$" || true

# ── 6. Final check ───────────────────────────────────────────────
echo "[6/6] Verifying site is accessible..."
HTTP=$(curl -so /dev/null -w "%{http_code}" --connect-timeout 5 http://localhost/ 2>/dev/null || echo "000")
[ "$HTTP" = "200" ] && echo "      Site OK (HTTP $HTTP)" || echo "      Site returned HTTP $HTTP — may need a moment to fully load"

# ── Done ─────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  DONE!"
echo "  URL:   http://$SERVER_IP/"
echo "  Login: $ADMIN_EMAIL"
echo "  Pass:  $ADMIN_PASS"
echo "========================================"
