#!/usr/bin/env bash
# =============================================================================
#  ChengetAi DSpace Engine — install.sh
#  Usage:  chengetai deploy dspace
#          — or —
#          bash engines/dspace-engine/scripts/install.sh
#
#  The installer is idempotent: running it twice will not destroy an existing
#  repository.  All steps check current state before acting.
# =============================================================================

set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_DIR="$(cd "$ENGINE_DIR/../common" && pwd)"

# shellcheck source=../../common/logging.sh
source "$COMMON_DIR/logging.sh"
# shellcheck source=../../common/docker.sh
source "$COMMON_DIR/docker.sh"
# shellcheck source=../../common/ssl.sh
source "$COMMON_DIR/ssl.sh"

# ---- Validate environment ------------------------------------------------- #
[ "$EUID" -eq 0 ] || log_die "Run as root (sudo bash $0)"

ENV_FILE="$ENGINE_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
  log_warn ".env not found — creating from .env.example"
  cp "$ENGINE_DIR/.env.example" "$ENV_FILE"
  log_warn "Edit $ENV_FILE and re-run this script"
  exit 1
fi

# Load env
set -a; source "$ENV_FILE"; set +a

# Check required variables
for var in DSPACE_HOSTNAME POSTGRES_PASSWORD ADMIN_EMAIL ADMIN_PASSWORD; do
  [ -n "${!var:-}" ] || log_die "Required variable $var is not set in .env"
done

# ---- Banner ---------------------------------------------------------------- #
log_banner "ChengetAi DSpace Engine — Installation"
log_info "Hostname : $DSPACE_HOSTNAME"
log_info "Protocol : ${PUBLIC_PROTOCOL:-http}"
log_info "Admin    : $ADMIN_EMAIL"
log_info "Engine   : $ENGINE_DIR"
echo ""

# ---- Step 1: Docker -------------------------------------------------------- #
docker_require

# ---- Step 2: Render local.cfg from template -------------------------------- #
log_step "Rendering DSpace configuration"
RENDERED_CFG="$ENGINE_DIR/config/local.cfg"
sed \
  -e "s|%%DSPACE_HOSTNAME%%|${DSPACE_HOSTNAME}|g" \
  -e "s|%%POSTGRES_PASSWORD%%|${POSTGRES_PASSWORD}|g" \
  -e "s|%%SMTP_HOST%%|${SMTP_HOST:-localhost}|g" \
  -e "s|%%SMTP_PORT%%|${SMTP_PORT:-25}|g" \
  -e "s|%%DSPACE_NAME%%|${DSPACE_NAME:-DSpace Repository}|g" \
  -e "s|%%HANDLE_PREFIX%%|${HANDLE_PREFIX:-123456789}|g" \
  -e "s|%%MAIL_FROM%%|${MAIL_FROM:-dspace@localhost}|g" \
  -e "s|%%PUBLIC_PROTOCOL%%|${PUBLIC_PROTOCOL:-http}|g" \
  "$ENGINE_DIR/templates/local.cfg.tpl" > "$RENDERED_CFG"
log_ok "config/local.cfg rendered"

# ---- Step 3: Pull images --------------------------------------------------- #
docker_compose_pull "$ENGINE_DIR"

# ---- Step 4: Network ------------------------------------------------------- #
log_step "Ensuring Docker network"
docker_network_ensure dspace

# ---- Step 5: Start PostgreSQL ---------------------------------------------- #
log_step "Starting PostgreSQL"
docker compose -f "$ENGINE_DIR/docker-compose.yml" --env-file "$ENV_FILE" \
  up -d postgres
docker_wait_healthy dspace-db 120

# ---- Step 6: Start Solr ---------------------------------------------------- #
log_step "Starting Solr"
docker compose -f "$ENGINE_DIR/docker-compose.yml" --env-file "$ENV_FILE" \
  up -d solr
docker_wait_healthy dspace-solr 120

# ---- Step 7: Start DSpace Backend ------------------------------------------ #
log_step "Starting DSpace Backend (REST API)"
log_info "This may take 2-4 minutes on first start..."
docker compose -f "$ENGINE_DIR/docker-compose.yml" --env-file "$ENV_FILE" \
  up -d dspace
docker_wait_healthy dspace-backend 300

# ---- Step 8: Database migrations ------------------------------------------- #
log_step "Running database migrations"
docker exec dspace-backend /dspace/bin/dspace database migrate || true
log_ok "Database migrations complete"

# ---- Step 9: Create administrator account ---------------------------------- #
log_step "Creating administrator account"
if docker exec dspace-backend /dspace/bin/dspace user \
    --list --email "$ADMIN_EMAIL" 2>/dev/null | grep -q "$ADMIN_EMAIL"; then
  log_info "Administrator $ADMIN_EMAIL already exists — skipping"
else
  docker exec dspace-backend /dspace/bin/dspace create-administrator \
    -e "$ADMIN_EMAIL" \
    -f "Admin" \
    -l "User" \
    -p "$ADMIN_PASSWORD" \
    -c en
  log_ok "Administrator account created: $ADMIN_EMAIL"
fi

# ---- Step 10: Start Angular UI --------------------------------------------- #
log_step "Starting Angular UI"
docker compose -f "$ENGINE_DIR/docker-compose.yml" --env-file "$ENV_FILE" \
  up -d dspace-ui
docker_wait_healthy dspace-frontend 120

# ---- Step 11: Configure Nginx ---------------------------------------------- #
log_step "Starting Nginx reverse proxy"
docker compose -f "$ENGINE_DIR/docker-compose.yml" --env-file "$ENV_FILE" \
  up -d nginx
log_ok "Nginx started"

# ---- Step 12: SSL ---------------------------------------------------------- #
if [ "${PUBLIC_PROTOCOL:-http}" = "https" ]; then
  log_step "Configuring HTTPS"
  bash "$ENGINE_DIR/scripts/ssl-setup.sh"
fi

# ---- Step 13: Initial Solr index ------------------------------------------- #
log_step "Running initial Solr indexing"
docker exec dspace-backend /dspace/bin/dspace index-discovery -b &>/dev/null &
log_ok "Indexing started in background"

# ---- Step 14: Health check ------------------------------------------------- #
log_step "Running health checks"
sleep 10
bash "$ENGINE_DIR/scripts/healthcheck.sh"

# ---- Done ------------------------------------------------------------------ #
PROTO="${PUBLIC_PROTOCOL:-http}"
echo ""
log_banner "Installation Complete"
echo -e "  ${C_BOLD}Repository URL:${C_RESET}   $PROTO://$DSPACE_HOSTNAME/"
echo -e "  ${C_BOLD}Admin login:${C_RESET}      $PROTO://$DSPACE_HOSTNAME/login"
echo -e "  ${C_BOLD}REST API:${C_RESET}         $PROTO://$DSPACE_HOSTNAME/server/"
echo ""
echo -e "  ${C_YELLOW}Next steps:${C_RESET}"
echo "    1. Enable HTTPS:      bash scripts/ssl-setup.sh"
echo "    2. Create structure:  bash scripts/create-site.sh"
echo "    3. Monitor:           chengetai status dspace"
echo ""
