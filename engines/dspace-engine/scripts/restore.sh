#!/usr/bin/env bash
# =============================================================================
#  ChengetAi DSpace Engine — restore.sh
#  Usage:  chengetai restore dspace [backup_timestamp_dir]
#          — or —
#          bash engines/dspace-engine/scripts/restore.sh /var/backups/chengetai/dspace/20250101_120000
# =============================================================================

set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_DIR="$(cd "$ENGINE_DIR/../common" && pwd)"

source "$COMMON_DIR/logging.sh"
source "$COMMON_DIR/backup.sh"
source "$COMMON_DIR/docker.sh"

ENV_FILE="$ENGINE_DIR/.env"
[ -f "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }

BACKUP_ROOT_DIR="${BACKUP_ROOT:-/var/backups/chengetai/dspace}"

log_banner "ChengetAi DSpace — Restore"

# ---- Locate backup directory ----------------------------------------------- #
RESTORE_DIR="${1:-}"
if [ -z "$RESTORE_DIR" ]; then
  backup_list "$BACKUP_ROOT_DIR"
  read -rp "Enter backup timestamp directory to restore from: " RESTORE_DIR
fi

[ -d "$RESTORE_DIR" ] || log_die "Backup directory not found: $RESTORE_DIR"
[ -f "$RESTORE_DIR/MANIFEST.txt" ] || log_warn "No MANIFEST.txt — directory may not be a valid backup"

log_info "Restoring from: $RESTORE_DIR"
cat "$RESTORE_DIR/MANIFEST.txt" 2>/dev/null || true
echo ""

read -rp "This will OVERWRITE the current database and assetstore. Continue? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { log_info "Restore cancelled"; exit 0; }

# ---- Stop backend services (keep DB running) ------------------------------- #
log_step "Stopping DSpace services"
docker compose -f "$ENGINE_DIR/docker-compose.yml" --env-file "$ENV_FILE" \
  stop dspace dspace-ui nginx 2>/dev/null || true

# ---- Restore database ------------------------------------------------------ #
log_step "Restoring PostgreSQL"
DB_FILE="$(ls "$RESTORE_DIR"/dspace-*.sql.gz 2>/dev/null | head -1 || true)"
[ -n "$DB_FILE" ] || log_die "No database backup found in $RESTORE_DIR"

# Drop and recreate schema
docker exec dspace-db psql -U dspace dspace \
  -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" &>/dev/null

restore_postgres dspace-db dspace dspace "$DB_FILE"

# ---- Restore assetstore ---------------------------------------------------- #
log_step "Restoring assetstore"
ASSET_FILE="$(ls "$RESTORE_DIR"/assetstore-*.tar.gz 2>/dev/null | head -1 || true)"
if [ -n "$ASSET_FILE" ]; then
  docker run --rm \
    -v dspace-assetstore:/dspace/assetstore \
    -v "$(dirname "$ASSET_FILE")":/backup \
    alpine \
    sh -c "rm -rf /dspace/assetstore/* && tar xzf /backup/$(basename "$ASSET_FILE") -C /dspace/assetstore"
  log_ok "Assetstore restored"
else
  log_warn "No assetstore backup found — skipping"
fi

# ---- Restart services ------------------------------------------------------ #
log_step "Restarting services"
docker compose -f "$ENGINE_DIR/docker-compose.yml" --env-file "$ENV_FILE" \
  up -d dspace
docker_wait_healthy dspace-backend 300

docker compose -f "$ENGINE_DIR/docker-compose.yml" --env-file "$ENV_FILE" \
  up -d dspace-ui nginx

# ---- Rebuild Solr index ---------------------------------------------------- #
log_step "Rebuilding Solr index"
docker exec dspace-backend /dspace/bin/dspace index-discovery -b &>/dev/null &
log_ok "Indexing started in background"

log_ok "Restore complete"
