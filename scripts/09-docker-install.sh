#!/bin/bash
# =================================================================
#  OPTION B: Docker-based DSpace install (EASIER / FASTER)
#  Runs DSpace 7.6 via Docker Compose — no manual compiling needed.
#  Run as root on hrepolyREP (192.168.26.3)
# =================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}==>${NC} $1"; }
ok()  { echo -e "${GREEN}[DONE]${NC} $1"; }
die() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

INSTALL_DIR="/opt/dspace-install"

[ "$EUID" -eq 0 ] || die "Run as root"

log "=== DSpace 7.6 Docker Installation — Harare Polytechnic ==="

# ---- Install Docker ----
log "Installing Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    ok "Docker installed"
else
    ok "Docker already installed: $(docker --version)"
fi

# ---- Install Docker Compose ----
log "Installing Docker Compose..."
if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null 2>&1; then
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
    curl -SL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
        -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ok "Docker Compose installed"
else
    ok "Docker Compose already installed"
fi

# ---- Clone / update repo ----
log "Setting up DSpace installation files..."
if [ ! -d "$INSTALL_DIR" ]; then
    git clone https://github.com/wgmasvix-hue/harare-polytechnic-dspace-installation-.git "$INSTALL_DIR"
else
    cd "$INSTALL_DIR" && git pull
fi
cd "$INSTALL_DIR"

# ---- Configure .env ----
if [ ! -f ".env" ]; then
    cp .env.example .env
    log "Created .env from example"

    # Prompt for passwords
    read -rp   "Server IP [192.168.26.3]: " SERVER_HOST
    SERVER_HOST=${SERVER_HOST:-192.168.26.3}
    read -rsp  "Database password: " DB_PASS; echo
    read -rsp  "DSpace admin password: " ADMIN_PASS; echo
    read -rp   "Admin email: " ADMIN_EMAIL

    sed -i "s|SERVER_HOST=.*|SERVER_HOST=${SERVER_HOST}|" .env
    sed -i "s|DSPACE_DB_PASSWORD=.*|DSPACE_DB_PASSWORD=${DB_PASS}|" .env
    sed -i "s|DSPACE_ADMIN_PASS=.*|DSPACE_ADMIN_PASS=${ADMIN_PASS}|" .env
    sed -i "s|DSPACE_ADMIN_EMAIL=.*|DSPACE_ADMIN_EMAIL=${ADMIN_EMAIL}|" .env

    # Update local.cfg with actual values
    sed -i "s|192.168.26.3|${SERVER_HOST}|g" config/local.cfg
    sed -i "s|DSpaceHrep2024!|${DB_PASS}|g" config/local.cfg
fi

# ---- Pull images and start ----
log "Pulling Docker images (requires internet — this may take 5-10 minutes)..."
docker compose pull

log "Starting DSpace services..."
docker compose up -d

# ---- Wait for DSpace to be ready ----
log "Waiting for DSpace to initialize (up to 3 minutes)..."
MAX_WAIT=180
ELAPSED=0
while ! curl -sf http://localhost:8080/server/api &>/dev/null; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
    [ $ELAPSED -ge $MAX_WAIT ] && { echo ""; die "DSpace did not start in ${MAX_WAIT}s. Check: docker compose logs dspace"; }
done
echo ""
ok "DSpace REST API is up"

# ---- Create admin account ----
log "Creating DSpace administrator account..."
source .env
docker exec dspace-backend /dspace/bin/dspace create-administrator \
    -e "${DSPACE_ADMIN_EMAIL}" \
    -f "Library" \
    -l "Admin" \
    -p "${DSPACE_ADMIN_PASS}" \
    -c en

ok "Administrator account created: ${DSPACE_ADMIN_EMAIL}"

# ---- Run initial indexing ----
log "Running initial Solr indexing..."
docker exec dspace-backend /dspace/bin/dspace index-discovery -b

ok "=== Docker installation complete! ==="
echo ""
echo "  DSpace UI:    http://$(source .env && echo $SERVER_HOST)/"
echo "  Admin login:  http://$(source .env && echo $SERVER_HOST)/login"
echo "  REST API:     http://$(source .env && echo $SERVER_HOST)/server/"
echo ""
echo "  Manage services:"
echo "    docker compose ps                    # see status"
echo "    docker compose logs -f dspace        # backend logs"
echo "    docker compose logs -f dspace-ui     # frontend logs"
echo "    docker compose restart               # restart all"
echo "    docker compose down                  # stop all"
echo ""
echo "  Next: Run  scripts/10-setup-collections.sh  to create communities"
