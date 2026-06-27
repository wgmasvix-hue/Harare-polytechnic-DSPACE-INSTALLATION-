#!/bin/bash
# =================================================================
#  ONE-COMMAND DSpace 7.6 Deploy — Harare Polytechnic
#  Fully non-interactive. Set variables below then run.
#
#  USAGE:
#  SERVER_IP="192.168.26.3" \
#  DB_PASS="YourDbPass" \
#  ADMIN_EMAIL="library@hrepoly.ac.zw" \
#  ADMIN_PASS="YourAdminPass" \
#  bash <(curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/harare-polytechnic-dspace-installation-/main/scripts/deploy-now.sh)
# =================================================================

set -euo pipefail

# ---- Config (from environment or auto-detected) ----
# SERVER_IP can be pre-set (e.g. for local installs); otherwise auto-detects public IP
SERVER_IP="${SERVER_IP:-$(curl -sf https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')}"
DB_PASS="${DB_PASS:-DSpaceHarare2024}"
ADMIN_EMAIL="${ADMIN_EMAIL:-library@hrepoly.ac.zw}"
ADMIN_PASS="${ADMIN_PASS:-Admin@Hrep2024}"
INSTALL_DIR="/opt/dspace-install"

G='\033[0;32m'; B='\033[0;34m'; R='\033[0;31m'; N='\033[0m'
log() { echo -e "\n${B}[$(date +%H:%M:%S)]${N} $1"; }
ok()  { echo -e "${G}  ✓ $1${N}"; }
die() { echo -e "${R}  ✗ $1${N}"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Harare Polytechnic — DSpace 7.6 Auto-Deploy        ║"
echo "║  Server: $SERVER_IP                          ║"
echo "╚══════════════════════════════════════════════════════╝"

# ---- 1. Install Docker ----
log "Installing Docker..."
if ! command -v docker &>/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    curl -fsSL https://get.docker.com | sh -s -- --quiet
    systemctl enable --now docker
fi
ok "Docker $(docker --version | grep -oP '[\d.]+ ' | head -1)"

# ---- 2. Install Docker Compose plugin ----
if ! docker compose version &>/dev/null 2>&1; then
    apt-get install -y -qq docker-compose-plugin
fi
ok "Docker Compose ready"

# ---- 3. Clone repo ----
log "Setting up DSpace files..."
if [ -d "$INSTALL_DIR/.git" ]; then
    git -C "$INSTALL_DIR" pull -q
else
    rm -rf "$INSTALL_DIR"
    git clone -q https://github.com/wgmasvix-hue/harare-polytechnic-dspace-installation-.git "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
ok "Files ready in $INSTALL_DIR"

# ---- 4. Write .env ----
log "Writing configuration..."
cat > .env <<ENV
SERVER_HOST=${SERVER_IP}
DSPACE_DB_PASSWORD=${DB_PASS}
DSPACE_ADMIN_EMAIL=${ADMIN_EMAIL}
DSPACE_ADMIN_PASS=${ADMIN_PASS}
SMTP_HOST=localhost
HANDLE_PREFIX=123456789
ENV
ok ".env written (SERVER_HOST=${SERVER_IP})"

# ---- 5. UFW firewall ----
log "Configuring firewall..."
if command -v ufw &>/dev/null; then
    ufw --force reset -q
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp   -q
    ufw allow 80/tcp   -q
    ufw allow 443/tcp  -q
    ufw --force enable -q
    ok "Firewall: 22, 80, 443 open"
fi

# ---- 6. Stop native nginx if running (frees port 80) ----
systemctl stop nginx 2>/dev/null || true
systemctl disable nginx 2>/dev/null || true
fuser -k 80/tcp 2>/dev/null || true

# ---- 7. Pull Docker images ----
log "Pulling Docker images (5-10 min on first run)..."
docker compose pull 2>&1 | grep -E 'Pulling|Pulled|already' | head -20 || true
ok "Images ready"

# ---- 8. Start services ----
log "Starting DSpace services..."
docker compose down --remove-orphans -q 2>/dev/null || true
docker compose up -d
ok "Containers started"

# ---- 9. Create Solr cores (first run) ----
log "Initialising Solr cores..."
sleep 20
docker exec dspace-solr bash -c "
  precreate-core search     /opt/solr/server/solr/search     2>/dev/null || true
  precreate-core statistics /opt/solr/server/solr/statistics 2>/dev/null || true
  precreate-core authority  /opt/solr/server/solr/authority  2>/dev/null || true
  precreate-core oai        /opt/solr/server/solr/oai        2>/dev/null || true
" 2>/dev/null && ok "Solr cores ready" || ok "Solr cores (may already exist)"
docker restart dspace-backend -q 2>/dev/null || true

# ---- 10. Wait for DSpace backend ----
log "Waiting for DSpace to initialise (3-4 minutes)..."
MAX=360; ELAPSED=0
printf "  Progress: "
until curl -sf http://localhost:8080/server/api &>/dev/null; do
    printf "."
    sleep 10; ELAPSED=$((ELAPSED+10))
    if [ $ELAPSED -ge $MAX ]; then
        echo ""
        die "Timed out after ${MAX}s. Check: docker compose logs dspace-backend"
    fi
done
echo " done"
ok "DSpace REST API is responding"

# ---- 11. Create admin account ----
log "Creating administrator account..."
docker exec dspace-backend /dspace/bin/dspace create-administrator \
    -e "$ADMIN_EMAIL" \
    -f "Library" \
    -l "Admin" \
    -p "$ADMIN_PASS" \
    -c en 2>/dev/null && ok "Admin account created" || ok "Admin may already exist"

# ---- 12. Initial Solr index ----
log "Running initial search index..."
docker exec dspace-backend /dspace/bin/dspace index-discovery -b &>/dev/null &
ok "Indexing started"

# ---- Done ----
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  INSTALLATION COMPLETE!                             ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║                                                     ║"
echo "║  Open in browser:  http://${SERVER_IP}/          ║"
echo "║  Admin login:      http://${SERVER_IP}/login     ║"
echo "║  Admin email:      ${ADMIN_EMAIL}     ║"
echo "║                                                     ║"
echo "║  Setup faculties:                                   ║"
echo "║    cd /opt/dspace-install                          ║"
echo "║    bash scripts/10-setup-collections.sh            ║"
echo "║                                                     ║"
echo "║  Service commands:                                  ║"
echo "║    docker compose ps         (status)              ║"
echo "║    docker compose logs -f    (live logs)           ║"
echo "║    docker compose restart    (restart all)         ║"
echo "╚══════════════════════════════════════════════════════╝"
