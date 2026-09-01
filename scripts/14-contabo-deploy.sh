#!/bin/bash
# =================================================================
#  DSpace 9 — Contabo VPS Deployment Script
#  Target: Ubuntu 22.04, 8GB RAM, Public IP
#  Harare Polytechnic Institutional Repository
#
#  Run as root on your Contabo VM:
#    ssh root@YOUR_CONTABO_IP
#    bash <(curl -fsSL https://raw.githubusercontent.com/wgmasvix-hue/harare-polytechnic-dspace-installation-/claude/dspace-harare-polytechnic-install-0asotw/scripts/14-contabo-deploy.sh)
# =================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "\n${BLUE}[$(date +%H:%M:%S)]==>${NC} $1"; }
ok()   { echo -e "${GREEN}  ✓${NC} $1"; }
warn() { echo -e "${YELLOW}  !${NC} $1"; }
die()  { echo -e "${RED}  ✗ FATAL:${NC} $1"; exit 1; }

[ "$EUID" -eq 0 ] || die "Run as root: sudo bash $0"
[ -f /etc/os-release ] && . /etc/os-release
[[ "$ID" == "ubuntu" ]] || warn "Script optimised for Ubuntu — proceeding anyway"

# ---- Detect public IP ----
PUBLIC_IP=$(curl -sf https://api.ipify.org 2>/dev/null || \
            curl -sf https://ifconfig.me 2>/dev/null || \
            hostname -I | awk '{print $1}')

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   HARARE POLYTECHNIC — DSpace 9 on Contabo VPS           ║"
echo "║   OS:  $PRETTY_NAME"
echo "║   RAM: $(free -h | awk '/^Mem:/{print $2}') total"
echo "║   IP:  $PUBLIC_IP (detected)"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Confirm or override IP
read -rp "Contabo public IP [$PUBLIC_IP]: " INPUT_IP
SERVER_IP="${INPUT_IP:-$PUBLIC_IP}"

read -rsp "Database password (strong, min 16 chars): " DB_PASS; echo
[ ${#DB_PASS} -lt 8 ] && die "Password too short"

read -rsp "DSpace admin password: " ADMIN_PASS; echo
read -rp  "Admin email address:   " ADMIN_EMAIL

echo ""
echo "  Server IP:    $SERVER_IP"
echo "  Admin email:  $ADMIN_EMAIL"
echo ""
read -rp "Proceed? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

# Full log
LOG="/var/log/dspace-install-$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
log "Full log: $LOG"

# ================================================================
#  STEP 1 — System update & essentials
# ================================================================
log "Step 1/8 — System update"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git unzip zip make nano \
    ca-certificates gnupg lsb-release \
    ufw fail2ban mailutils net-tools
ok "System updated"

# ================================================================
#  STEP 2 — Firewall (UFW)
# ================================================================
log "Step 2/8 — Configuring firewall"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    comment "SSH"
ufw allow 80/tcp    comment "HTTP"
ufw allow 443/tcp   comment "HTTPS"
ufw --force enable
ok "Firewall: ports 22, 80, 443 open — all others blocked"

# ================================================================
#  STEP 3 — Fail2ban (SSH brute-force protection)
# ================================================================
log "Step 3/8 — Configuring fail2ban"
cat > /etc/fail2ban/jail.local <<'F2B'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled  = true
port     = 22
logpath  = /var/log/auth.log
maxretry = 3
F2B
systemctl enable --now fail2ban
ok "Fail2ban active — SSH locked after 3 failed attempts"

# ================================================================
#  STEP 4 — Docker
# ================================================================
log "Step 4/8 — Installing Docker"
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    ok "Docker installed: $(docker --version)"
else
    ok "Docker already present: $(docker --version)"
fi

# Install Docker Compose plugin
if ! docker compose version &>/dev/null 2>&1; then
    apt-get install -y docker-compose-plugin
fi
ok "Docker Compose: $(docker compose version)"

# ================================================================
#  STEP 5 — Clone repo & configure
# ================================================================
log "Step 5/8 — Setting up DSpace installation files"
INSTALL_DIR="/opt/dspace-install"
if [ -d "$INSTALL_DIR" ]; then
    cd "$INSTALL_DIR" && git pull
else
    git clone https://github.com/wgmasvix-hue/harare-polytechnic-dspace-installation-.git "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# Write .env
cat > .env <<ENV
SERVER_HOST=${SERVER_IP}
DSPACE_DB_PASSWORD=${DB_PASS}
DSPACE_ADMIN_EMAIL=${ADMIN_EMAIL}
DSPACE_ADMIN_PASS=${ADMIN_PASS}
SMTP_HOST=localhost
HANDLE_PREFIX=123456789
ENV

# Update local.cfg with actual IP
sed -i "s|192\.168\.26\.3|${SERVER_IP}|g" config/local.cfg
sed -i "s|DSpaceHrep2024!|${DB_PASS}|g"  config/local.cfg
ok "Configuration written"

# ================================================================
#  STEP 6 — Pull Docker images & start DSpace
# ================================================================
log "Step 6/8 — Pulling Docker images (5-15 minutes)"
docker compose pull

log "Starting DSpace services..."
docker compose up -d

# ================================================================
#  STEP 7 — Wait for DSpace to initialise
# ================================================================
log "Step 7/8 — Waiting for DSpace to initialise (up to 4 minutes)"
MAX=240; ELAPSED=0
echo -n "  Waiting"
until curl -sf "http://localhost:8080/server/api" &>/dev/null; do
    sleep 5; ELAPSED=$((ELAPSED+5)); echo -n "."
    [ $ELAPSED -ge $MAX ] && { echo ""; die "Timed out. Check: docker compose logs dspace-backend"; }
done
echo " ready!"
ok "DSpace REST API is responding"

# ================================================================
#  STEP 8 — Create admin & index
# ================================================================
log "Step 8/8 — Creating administrator account"
docker exec dspace-backend /dspace/bin/dspace create-administrator \
    -e "$ADMIN_EMAIL" -f "Library" -l "Admin" -p "$ADMIN_PASS" -c en
ok "Admin account created: $ADMIN_EMAIL"

log "Running initial Solr index"
docker exec dspace-backend /dspace/bin/dspace index-discovery -b &
ok "Indexing started in background"

# ================================================================
#  DONE
# ================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║   INSTALLATION COMPLETE                                     ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                             ║"
echo "║   DSpace UI:    http://${SERVER_IP}/                       "
echo "║   Admin login:  http://${SERVER_IP}/login                  "
echo "║   REST API:     http://${SERVER_IP}/server/                "
echo "║                                                             ║"
echo "║   Next steps:                                              ║"
echo "║   1. Create faculty structure:                             ║"
echo "║      cd /opt/dspace-install && make setup-collections       ║"
echo "║   2. Enable HTTPS:  make ssl                               ║"
echo "║   3. Monitor:       make status                            ║"
echo "║                                                             ║"
echo "║   Full log: $LOG"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
