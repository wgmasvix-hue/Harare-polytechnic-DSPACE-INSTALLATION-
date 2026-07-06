#!/usr/bin/env bash
# =============================================================================
#  ChengetAi DSpace Engine — update.sh
#  Pulls latest DSpace images and performs a rolling restart.
#  Usage:  chengetai update dspace
#          — or —
#          bash engines/dspace-engine/scripts/update.sh [--major]
#
#  Without --major: pulls the same image tag (patch/minor updates within tag)
#  With    --major: prompts to change DSPACE_*_TAG values in .env
# =============================================================================

set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_DIR="$(cd "$ENGINE_DIR/../common" && pwd)"

source "$COMMON_DIR/logging.sh"
source "$COMMON_DIR/docker.sh"

ENV_FILE="$ENGINE_DIR/.env"
[ -f "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }

MAJOR_UPGRADE="${1:-}"

log_banner "ChengetAi DSpace — Update"

# ---- Optional: major version bump ----------------------------------------- #
if [ "$MAJOR_UPGRADE" = "--major" ]; then
  log_warn "Major version upgrade — edit .env to change DSPACE_*_TAG values"
  log_info "Current tags:"
  grep "DSPACE_.*_TAG" "$ENV_FILE" || true
  read -rp "Edit .env now? [y/N]: " EDIT
  [[ "$EDIT" =~ ^[Yy]$ ]] && "${EDITOR:-nano}" "$ENV_FILE"
  set -a; source "$ENV_FILE"; set +a
fi

# ---- Backup before update -------------------------------------------------- #
log_step "Creating pre-update backup"
bash "$ENGINE_DIR/scripts/backup.sh"

# ---- Pull new images ------------------------------------------------------- #
log_step "Pulling updated Docker images"
docker compose -f "$ENGINE_DIR/docker-compose.yml" --env-file "$ENV_FILE" pull

# ---- Rolling restart ------------------------------------------------------- #
log_step "Restarting DSpace Backend"
docker compose -f "$ENGINE_DIR/docker-compose.yml" --env-file "$ENV_FILE" \
  up -d --no-deps dspace
docker_wait_healthy dspace-backend 300

log_step "Restarting Angular UI"
docker compose -f "$ENGINE_DIR/docker-compose.yml" --env-file "$ENV_FILE" \
  up -d --no-deps dspace-ui
docker_wait_healthy dspace-frontend 120

log_step "Restarting Nginx"
docker compose -f "$ENGINE_DIR/docker-compose.yml" --env-file "$ENV_FILE" \
  up -d --no-deps nginx

# ---- Run migrations (safe on same version — no-op) ------------------------- #
log_step "Running database migrations"
docker exec dspace-backend /dspace/bin/dspace database migrate || true

# ---- Rebuild Solr index ---------------------------------------------------- #
log_step "Rebuilding Solr index after update"
docker exec dspace-backend /dspace/bin/dspace index-discovery -b &>/dev/null &

# ---- Health check ---------------------------------------------------------- #
log_step "Running health checks"
sleep 10
bash "$ENGINE_DIR/scripts/healthcheck.sh"

log_ok "Update complete"
