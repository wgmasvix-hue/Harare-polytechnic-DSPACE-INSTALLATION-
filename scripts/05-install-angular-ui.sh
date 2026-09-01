#!/bin/bash
# Step 5: Install DSpace Angular frontend (UI)
# Run as root on hrepolyREP (192.168.26.3)

set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
ok()  { echo -e "${GREEN}[OK]${NC} $1"; }

DSPACE_VERSION="9.0"
UI_DIR="/opt/dspace-ui"
SERVER_HOSTNAME="${DSPACE_HOSTNAME:-192.168.26.3}"
NODE_VERSION=18

log "=== DSpace Angular UI Installation ==="

# ---- Install Node.js ----
log "Installing Node.js $NODE_VERSION..."
if ! command -v node &>/dev/null || [[ "$(node -v)" != v${NODE_VERSION}* ]]; then
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - 2>/dev/null || \
    curl -fsSL "https://rpm.nodesource.com/setup_${NODE_VERSION}.x" | bash -
    apt-get install -y nodejs 2>/dev/null || dnf install -y nodejs 2>/dev/null || true
fi

node -v && npm -v
ok "Node.js installed"

# ---- Install Yarn ----
log "Installing Yarn..."
npm install -g yarn 2>/dev/null || true

# ---- Download DSpace Angular ----
log "Downloading DSpace Angular UI $DSPACE_VERSION..."
mkdir -p "$UI_DIR"
cd /build
if [ ! -f "dspace-angular.tar.gz" ]; then
    wget -q "https://github.com/DSpace/dspace-angular/archive/refs/tags/dspace-${DSPACE_VERSION}.tar.gz" \
        -O dspace-angular.tar.gz
fi
tar xzf dspace-angular.tar.gz -C "$UI_DIR" --strip-components=1
ok "Angular UI extracted to $UI_DIR"

# ---- Configure Angular UI ----
log "Configuring Angular UI..."
cat > "$UI_DIR/config/config.example.yml" <<ANGULARCFG
ui:
  ssl: false
  host: ${SERVER_HOSTNAME}
  port: 4000
  nameSpace: /
  rateLimiter:
    windowMs: 60000
    max: 500

rest:
  ssl: false
  host: ${SERVER_HOSTNAME}
  port: 8080
  nameSpace: /server
ANGULARCFG

cp "$UI_DIR/config/config.example.yml" "$UI_DIR/config/config.yml"
ok "Angular config written"

# ---- Build Angular UI ----
log "Installing npm dependencies (this may take 10+ minutes)..."
cd "$UI_DIR"
yarn install --frozen-lockfile 2>/dev/null || npm ci

log "Building Angular UI for production..."
yarn build:prod 2>/dev/null || npm run build:prod
ok "Angular UI built"

# ---- Create systemd service for UI ----
log "Creating systemd service for DSpace UI..."
cat > /etc/systemd/system/dspace-ui.service <<EOF
[Unit]
Description=DSpace Angular UI
After=network.target tomcat.service

[Service]
Type=simple
User=dspace
WorkingDirectory=${UI_DIR}
ExecStart=/usr/bin/yarn start:prod
ExecStop=/bin/kill -SIGTERM \$MAINPID
Restart=on-failure
RestartSec=10
Environment=NODE_ENV=production
Environment=DSPACE_REST_HOST=${SERVER_HOSTNAME}
Environment=DSPACE_REST_PORT=8080
Environment=DSPACE_REST_SSL=false
Environment=DSPACE_REST_NAMESPACE=/server

[Install]
WantedBy=multi-user.target
EOF

chown -R dspace:dspace "$UI_DIR"
systemctl daemon-reload
systemctl enable dspace-ui
systemctl start dspace-ui

ok "DSpace Angular UI started"
echo ""
echo "UI available at: http://${SERVER_HOSTNAME}:4000"
echo ""
echo "Next step: Run  scripts/06-create-admin.sh"
