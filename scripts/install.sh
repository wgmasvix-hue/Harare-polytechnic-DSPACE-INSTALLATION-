#!/bin/bash
# =================================================================
#  DSpace 7.6 — Universal Installer — Harare Polytechnic
#  Ubuntu 20.04 / 22.04 / 24.04 | Contabo VPS | Local LAN server
#
#  Quick install (non-interactive):
#    bash <(curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/harare-polytechnic-dspace-installation-/claude/dspace-harare-polytechnic-install-0asotw/scripts/install.sh)
#
#  Local server:
#    SERVER_IP="192.168.26.3" bash <(curl -fsSL <same url>)
#
#  Flags:
#    --fresh    Wipe all data and reinstall from scratch
#    --update   Pull latest images, restart (keeps all data)
#    --status   Show current container status and exit
# =================================================================
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' B='\033[0;34m' C='\033[0;36m' W='\033[1;37m' N='\033[0m'
ok()   { echo -e "${G}  ✓ $*${N}"; }
warn() { echo -e "${Y}  ! $*${N}"; }
err()  { echo -e "${R}  ✗ $*${N}"; exit 1; }
hdr()  { echo -e "\n${C}── $* ──────────────────────────────────${N}"; }

# ── Parse flags ──────────────────────────────────────────────────
MODE="install"   # install | fresh | update | status
for arg in "$@"; do
  case "$arg" in
    --fresh)  MODE="fresh"  ;;
    --update) MODE="update" ;;
    --status) MODE="status" ;;
  esac
done

# ── Defaults ─────────────────────────────────────────────────────
DIR="/opt/dspace"
IMAGES_TAG="dspace-7.6.3"
AUTO_IP=$(curl -sf --connect-timeout 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')

SERVER_IP="${SERVER_IP:-$AUTO_IP}"
DB_PASS="${DB_PASS:-DSpaceHarare2024}"
ADMIN_EMAIL="${ADMIN_EMAIL:-library@hrepoly.ac.zw}"
ADMIN_PASS="${ADMIN_PASS:-AdminHarare2024}"
SITE_NAME="${SITE_NAME:-Harare Polytechnic Institutional Repository}"

# ── Banner ───────────────────────────────────────────────────────
echo ""
echo -e "${W}╔══════════════════════════════════════════════════════╗${N}"
echo -e "${W}║   DSpace 7.6 — Harare Polytechnic                   ║${N}"
echo -e "${W}║   Universal Installer                                ║${N}"
echo -e "${W}╚══════════════════════════════════════════════════════╝${N}"
echo ""

# ── Status mode ──────────────────────────────────────────────────
if [ "$MODE" = "status" ]; then
    if [ -f "$DIR/docker-compose.yml" ]; then
        echo "Install directory: $DIR"
        docker compose -f "$DIR/docker-compose.yml" ps
    else
        warn "DSpace not installed at $DIR"
    fi
    exit 0
fi

# ── Interactive prompts (only when running from a terminal) ───────
if [ -t 0 ] && [ "$MODE" != "update" ]; then
    echo -e "${B}Press Enter to accept [defaults shown in brackets]${N}"
    echo ""

    read -rp "  Server IP address  [$SERVER_IP]: " _in
    SERVER_IP="${_in:-$SERVER_IP}"

    read -rp "  Admin email        [$ADMIN_EMAIL]: " _in
    ADMIN_EMAIL="${_in:-$ADMIN_EMAIL}"

    read -rsp "  Admin password     [AdminHarare2024]: " _in; echo ""
    ADMIN_PASS="${_in:-$ADMIN_PASS}"

    read -rsp "  DB password        [DSpaceHarare2024]: " _in; echo ""
    DB_PASS="${_in:-$DB_PASS}"

    echo ""
    echo -e "${W}  Installing DSpace on: http://$SERVER_IP/${N}"
    echo -e "${W}  Mode: $MODE${N}"
    echo ""
    read -rp "  Continue? [Y/n]: " _yn
    [[ "${_yn:-Y}" =~ ^[Nn] ]] && { echo "Aborted."; exit 0; }
fi

echo ""
echo -e "  ${B}Server IP:${N}  $SERVER_IP"
echo -e "  ${B}Mode:${N}      $MODE"
echo -e "  ${B}Directory:${N} $DIR"
echo ""

# ═════════════════════════════════════════════════════════════════
hdr "Step 1 — Docker"
# ═════════════════════════════════════════════════════════════════
if ! command -v docker &>/dev/null; then
    echo "  Installing Docker..."
    export DEBIAN_FRONTEND=noninteractive
    curl -fsSL https://get.docker.com | sh -s -- --quiet
    systemctl enable --now docker
    ok "Docker installed"
else
    ok "Docker $(docker --version | grep -oP '[\d.]+' | head -1)"
fi

if ! docker compose version &>/dev/null 2>&1; then
    apt-get install -y -qq docker-compose-plugin 2>/dev/null || true
fi
ok "Docker Compose $(docker compose version --short 2>/dev/null || echo 'ready')"

# ═════════════════════════════════════════════════════════════════
hdr "Step 2 — Port 80"
# ═════════════════════════════════════════════════════════════════
if systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl stop nginx && systemctl disable nginx
    ok "Stopped system nginx"
fi
fuser -k 80/tcp 2>/dev/null || true
ok "Port 80 is free"

# ═════════════════════════════════════════════════════════════════
hdr "Step 3 — Configuration files"
# ═════════════════════════════════════════════════════════════════
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
      dspace__P__server__url: "http://${SERVER_IP}/server"
      dspace__P__ui__url:     "http://${SERVER_IP}"
      dspace__P__name:        "${SITE_NAME}"
      dspace__P__hostname:    "${SERVER_IP}"
      mail__P__from__address: "dspace@hrepoly.ac.zw"
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
      DSPACE_UI_SSL:        "false"
      DSPACE_UI_HOST:       "${SERVER_IP}"
      DSPACE_UI_PORT:       "4000"
      DSPACE_UI_NAMESPACE:  "/"
      DSPACE_REST_SSL:      "false"
      DSPACE_REST_HOST:     "${SERVER_IP}"
      DSPACE_REST_PORT:     "80"
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
      - ./config/branding:/etc/nginx/branding:ro
    ports: ["80:80"]
COMPOSE

# ── nginx.conf ───────────────────────────────────────────────────
cat > config/nginx.conf << 'NGINX'
upstream dspace_backend  { server dspace-backend:8080;  keepalive 16; }
upstream dspace_frontend { server dspace-frontend:4000; keepalive 16; }

server {
    listen 80;
    server_name _;
    client_max_body_size 512M;

    # HP Branding — inject stylesheet into every page
    sub_filter_types text/html;
    sub_filter '</head>' '<link rel="stylesheet" href="/hp-brand.css"></head>';
    sub_filter_once on;

    location = /hp-brand.css {
        alias /etc/nginx/branding/hp-brand.css;
        add_header Cache-Control "public, max-age=86400";
    }
    location = /hp-logo.svg {
        alias /etc/nginx/branding/hp-logo.svg;
        add_header Cache-Control "public, max-age=86400";
    }

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

# ── HP Branding files ─────────────────────────────────────────────
cat > config/branding/hp-logo.svg << 'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 56" height="44" role="img">
  <rect x="0" y="2" width="52" height="52" rx="5" fill="#FFD100"/>
  <text x="5" y="44" font-family="Arial,sans-serif" font-size="38" font-weight="900" fill="#006633">HP</text>
  <rect x="60" y="2" width="2" height="52" fill="#006633" opacity="0.3"/>
  <text x="72" y="22" font-family="Arial,sans-serif" font-size="15" font-weight="700" fill="#006633" letter-spacing="1">HARARE POLYTECHNIC</text>
  <text x="72" y="44" font-family="Arial,sans-serif" font-size="11" fill="#444">Institutional Repository</text>
</svg>
SVG

cat > config/branding/hp-brand.css << 'CSS'
/* Harare Polytechnic DSpace Branding — HP Green #006633, HP Gold #FFD100 */

ds-root ds-header .navbar,
ds-root ds-header nav.navbar {
  background-color: #006633 !important;
  border-bottom: 3px solid #FFD100;
}
ds-root ds-header .navbar-brand img { content: url('/hp-logo.svg'); height: 44px; width: auto; }
ds-root ds-header .navbar-brand span { display: none; }
ds-root ds-header .nav-link { color: rgba(255,255,255,0.9) !important; }
ds-root ds-header .nav-link:hover { color: #FFD100 !important; }

ds-root .btn-primary { background-color: #006633 !important; border-color: #006633 !important; }
ds-root .btn-primary:hover { background-color: #004d26 !important; border-color: #004d26 !important; }

ds-root a:not(.btn):not(.nav-link):not(.navbar-brand) { color: #006633; }
ds-root a:not(.btn):not(.nav-link):not(.navbar-brand):hover { color: #004d26; }

ds-root .page-item.active .page-link { background-color: #006633 !important; border-color: #006633 !important; }
ds-root .page-link { color: #006633 !important; }

ds-root ds-search-sidebar .card-header { background-color: #006633 !important; color: #fff !important; }

ds-root ds-footer footer,
ds-root footer {
  background-color: #006633 !important;
  color: rgba(255,255,255,0.85) !important;
  border-top: 3px solid #FFD100;
}
ds-root ds-footer footer a,
ds-root footer a { color: #FFD100 !important; }

ds-root ds-home-page .jumbotron,
ds-root .home-header-wrapper {
  background: linear-gradient(135deg, #006633 0%, #004d26 100%) !important;
  color: #fff !important;
}
ds-root ds-home-page .jumbotron h1,
ds-root .home-header-wrapper h1 { color: #FFD100 !important; }
CSS

ok "docker-compose.yml, nginx.conf, and HP branding written"

# ═════════════════════════════════════════════════════════════════
hdr "Step 4 — Containers"
# ═════════════════════════════════════════════════════════════════
if [ "$MODE" = "fresh" ]; then
    warn "Fresh mode — removing all existing data volumes..."
    docker compose down -v --remove-orphans 2>/dev/null || true
    ok "Old data removed"
elif [ "$MODE" = "update" ]; then
    echo "  Update mode — keeping all data"
    docker compose down --remove-orphans 2>/dev/null || true
else
    docker compose down --remove-orphans 2>/dev/null || true
fi

echo "  Pulling images (5-10 min on first run)..."
docker compose pull
docker compose up -d
ok "All containers started"

# ═════════════════════════════════════════════════════════════════
hdr "Step 5 — Waiting for DSpace"
# ═════════════════════════════════════════════════════════════════
echo "  Backend initialising (DB schema + Solr index) — 4-6 min..."
printf "  "
ELAPSED=0
until curl -sf --connect-timeout 5 http://localhost:8080/server/api &>/dev/null; do
    printf "."
    sleep 10
    ELAPSED=$((ELAPSED+10))
    if [ $ELAPSED -ge 660 ]; then
        echo ""
        err "Backend not ready after 11 min. Run: docker logs dspace-backend"
    fi
done
ok "Backend ready (${ELAPSED}s)"

echo "  Angular UI starting..."
printf "  "
ELAPSED=0
until curl -sf --connect-timeout 5 http://localhost:4000/ &>/dev/null; do
    printf "."
    sleep 10
    ELAPSED=$((ELAPSED+10))
    if [ $ELAPSED -ge 360 ]; then
        echo ""
        err "Frontend not ready after 6 min. Run: docker logs dspace-frontend"
    fi
done
ok "UI ready (${ELAPSED}s)"

# ═════════════════════════════════════════════════════════════════
hdr "Step 6 — Admin account"
# ═════════════════════════════════════════════════════════════════
if [ "$MODE" != "update" ]; then
    docker exec dspace-backend /dspace/bin/dspace create-administrator \
        -e "$ADMIN_EMAIL" -f Library -l Admin -p "$ADMIN_PASS" -c en 2>&1 \
        | grep -Ev "^$|^log4j" || true
    ok "Admin account: $ADMIN_EMAIL"
else
    ok "Update mode — admin account unchanged"
fi

# ═════════════════════════════════════════════════════════════════
hdr "All done"
# ═════════════════════════════════════════════════════════════════
HTTP=$(curl -so /dev/null -w "%{http_code}" --connect-timeout 5 http://localhost/ 2>/dev/null || echo "000")

echo ""
echo -e "${W}╔══════════════════════════════════════════════════════╗${N}"
echo -e "${W}║   INSTALLATION COMPLETE                              ║${N}"
echo -e "${W}╠══════════════════════════════════════════════════════╣${N}"
printf "${W}║${N}   %-50s ${W}║${N}\n" ""
printf "${W}║${N}   %-50s ${W}║${N}\n" "URL:    http://$SERVER_IP/"
printf "${W}║${N}   %-50s ${W}║${N}\n" "Login:  http://$SERVER_IP/login"
printf "${W}║${N}   %-50s ${W}║${N}\n" "Email:  $ADMIN_EMAIL"
printf "${W}║${N}   %-50s ${W}║${N}\n" "Pass:   $ADMIN_PASS"
printf "${W}║${N}   %-50s ${W}║${N}\n" ""
printf "${W}║${N}   %-50s ${W}║${N}\n" "Site HTTP status: $HTTP"
printf "${W}║${N}   %-50s ${W}║${N}\n" ""
echo -e "${W}╠══════════════════════════════════════════════════════╣${N}"
echo -e "${W}║   Useful commands (run in /opt/dspace):              ║${N}"
echo -e "${W}║   docker compose ps          — container status      ║${N}"
echo -e "${W}║   docker compose logs -f     — live logs             ║${N}"
echo -e "${W}║   docker compose restart     — restart all           ║${N}"
echo -e "${W}║   bash install.sh --update   — update images         ║${N}"
echo -e "${W}║   bash install.sh --fresh    — full wipe + reinstall ║${N}"
echo -e "${W}║   bash install.sh --status   — show container status ║${N}"
echo -e "${W}╚══════════════════════════════════════════════════════╝${N}"
echo ""
