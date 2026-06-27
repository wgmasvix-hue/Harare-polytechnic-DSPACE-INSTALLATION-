#!/bin/bash
# =================================================================
#  ONE-COMMAND DSpace 7.6 Deploy — Harare Polytechnic
#  Fully non-interactive. Works on Contabo VPS or local server.
#
#  USAGE — Contabo VPS (auto-detects public IP):
#    bash <(curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/harare-polytechnic-dspace-installation-/claude/dspace-harare-polytechnic-install-0asotw/scripts/deploy-now.sh)
#
#  USAGE — Local server (set IP explicitly):
#    SERVER_IP="192.168.26.3" bash <(curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/harare-polytechnic-dspace-installation-/claude/dspace-harare-polytechnic-install-0asotw/scripts/deploy-now.sh)
#
#  USAGE — Custom passwords:
#    SERVER_IP="192.168.26.3" DB_PASS="MyPass123" ADMIN_PASS="Admin456" \
#    bash <(curl -fsSL ...)
# =================================================================

set -euo pipefail

# ---- Config (env vars take priority; sane defaults otherwise) ----
SERVER_IP="${SERVER_IP:-$(curl -sf --connect-timeout 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')}"
DB_PASS="${DB_PASS:-DSpaceHarare2024}"
ADMIN_EMAIL="${ADMIN_EMAIL:-library@hrepoly.ac.zw}"
ADMIN_PASS="${ADMIN_PASS:-AdminHarare2024}"
INSTALL_DIR="/opt/dspace-install"
REPO_URL="https://github.com/wgmasvix-hue/harare-polytechnic-dspace-installation-.git"
REPO_BRANCH="claude/dspace-harare-polytechnic-install-0asotw"

G='\033[0;32m'; B='\033[0;34m'; R='\033[0;31m'; Y='\033[0;33m'; N='\033[0m'
log()  { echo -e "\n${B}[$(date +%H:%M:%S)]${N} $1"; }
ok()   { echo -e "${G}  ✓ $1${N}"; }
warn() { echo -e "${Y}  ! $1${N}"; }
die()  { echo -e "${R}  ✗ $1${N}"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Harare Polytechnic — DSpace 7.6 Auto-Deploy        ║"
printf "║  Server IP: %-41s║\n" "$SERVER_IP"
echo "╚══════════════════════════════════════════════════════╝"

# ---- 1. Install Docker ----
log "Step 1/10 — Installing Docker..."
if ! command -v docker &>/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    curl -fsSL https://get.docker.com | sh -s -- --quiet
    systemctl enable --now docker
    ok "Docker installed"
else
    ok "Docker already present: $(docker --version | grep -oP '[\d.]+' | head -1)"
fi

# ---- 2. Install Docker Compose plugin ----
log "Step 2/10 — Checking Docker Compose..."
if ! docker compose version &>/dev/null 2>&1; then
    apt-get install -y -qq docker-compose-plugin
fi
ok "Docker Compose $(docker compose version --short 2>/dev/null || echo 'ready')"

# ---- 3. Free port 80 (stop native nginx if running) ----
log "Step 3/10 — Freeing port 80..."
if systemctl is-active --quiet nginx 2>/dev/null; then
    systemctl stop nginx
    systemctl disable nginx
    ok "Stopped system nginx"
fi
fuser -k 80/tcp 2>/dev/null || true
ok "Port 80 is free"

# ---- 4. Clone / update repo ----
log "Step 4/10 — Downloading DSpace configuration..."
if [ -d "$INSTALL_DIR/.git" ]; then
    CURRENT_BRANCH=$(git -C "$INSTALL_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    if [ "$CURRENT_BRANCH" = "$REPO_BRANCH" ]; then
        git -C "$INSTALL_DIR" pull -q origin "$REPO_BRANCH" && ok "Repo updated" || warn "Pull failed; using existing files"
    else
        warn "Existing repo on different branch ($CURRENT_BRANCH) — re-cloning..."
        rm -rf "$INSTALL_DIR"
        git clone -q -b "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
        ok "Repo cloned (fresh)"
    fi
else
    rm -rf "$INSTALL_DIR"
    git clone -q -b "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
    ok "Repo cloned to $INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# ---- 5. Write .env ----
log "Step 5/10 — Writing configuration..."
cat > .env <<ENV
SERVER_HOST=${SERVER_IP}
DSPACE_DB_PASSWORD=${DB_PASS}
SMTP_HOST=localhost
HANDLE_PREFIX=123456789
ENV

# Patch local.cfg with correct IP and password
sed -i \
    -e "s|144\.91\.125\.128|${SERVER_IP}|g" \
    -e "s|192\.168\.26\.3|${SERVER_IP}|g" \
    -e "s|DSpaceHarare2024|${DB_PASS}|g" \
    -e "s|DSpaceHrep2024[^\"']*|${DB_PASS}|g" \
    config/local.cfg
ok ".env and local.cfg configured for $SERVER_IP"

# ---- 6. Firewall ----
log "Step 6/10 — Configuring firewall..."
if command -v ufw &>/dev/null; then
    ufw --force reset -q 2>/dev/null || true
    ufw default deny incoming  -q 2>/dev/null || true
    ufw default allow outgoing -q 2>/dev/null || true
    ufw allow 22/tcp  -q 2>/dev/null || true
    ufw allow 80/tcp  -q 2>/dev/null || true
    ufw allow 443/tcp -q 2>/dev/null || true
    ufw --force enable -q 2>/dev/null || true
    ok "Firewall: 22, 80, 443 open"
else
    warn "ufw not found — skipping firewall config"
fi

# ---- 7. Pull Docker images ----
log "Step 7/10 — Pulling Docker images (5-10 min on first run)..."
docker compose pull 2>&1 | grep -E "Pulling|Pulled|already present|up-to-date" || true
ok "Images ready"

# ---- 8. Start services ----
log "Step 8/10 — Starting DSpace services..."
docker compose down --remove-orphans -q 2>/dev/null || true
docker compose up -d
ok "All containers started"

# ---- 9. Wait for DSpace backend ----
log "Step 9/10 — Waiting for DSpace to initialise (4-6 minutes first time)..."
echo "  Solr will create 4 DSpace cores, then DSpace backend starts..."
MAX=480; ELAPSED=0
printf "  Progress: "
until curl -sf --connect-timeout 5 http://localhost:8080/server/api &>/dev/null; do
    printf "."
    sleep 10
    ELAPSED=$((ELAPSED+10))
    if [ $ELAPSED -ge $MAX ]; then
        echo ""
        echo ""
        warn "Timed out after ${MAX}s. DSpace may still be initialising."
        echo "  Check status:  docker compose ps"
        echo "  Check logs:    docker compose logs dspace-backend"
        echo "  Check Solr:    curl http://localhost:8983/solr/"
        echo ""
        echo "  Once ready, create admin manually:"
        echo "  docker exec dspace-backend /dspace/bin/dspace create-administrator \\"
        echo "    -e $ADMIN_EMAIL -f Library -l Admin -p $ADMIN_PASS -c en"
        exit 0
    fi
done
echo " done"
ok "DSpace REST API is responding at http://$SERVER_IP/server/api"

# ---- 10. Create admin account ----
log "Step 10/10 — Creating administrator account..."
docker exec dspace-backend /dspace/bin/dspace create-administrator \
    -e "$ADMIN_EMAIL" \
    -f "Library" \
    -l "Admin" \
    -p "$ADMIN_PASS" \
    -c en 2>&1 | grep -v "^$" || true
ok "Admin account: $ADMIN_EMAIL"

# Initial search index (runs in background)
docker exec -d dspace-backend /dspace/bin/dspace index-discovery -b 2>/dev/null || true

# ---- Done ----
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           INSTALLATION COMPLETE!                        ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║                                                          ║"
printf "║  Open in browser:  http://%-33s║\n" "$SERVER_IP/"
printf "║  Admin login:      http://%-33s║\n" "$SERVER_IP/login"
printf "║  Admin email:      %-36s║\n" "$ADMIN_EMAIL"
echo "║                                                          ║"
echo "║  Setup HP Faculties & Collections:                      ║"
echo "║    cd /opt/dspace-install                               ║"
echo "║    bash scripts/10-setup-collections.sh                 ║"
echo "║                                                          ║"
echo "║  Useful commands:                                        ║"
echo "║    docker compose ps          # container status        ║"
echo "║    docker compose logs -f     # live logs               ║"
echo "║    docker compose restart     # restart all             ║"
echo "╚══════════════════════════════════════════════════════════╝"
