#!/usr/bin/env bash
# =============================================================================
#  ChengetAi DSpace Engine — backup.sh
#  Usage:  chengetai backup dspace
#          — or —
#          bash engines/dspace-engine/scripts/backup.sh
# =============================================================================

set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_DIR="$(cd "$ENGINE_DIR/../common" && pwd)"

source "$COMMON_DIR/logging.sh"
source "$COMMON_DIR/backup.sh"

ENV_FILE="$ENGINE_DIR/.env"
[ -f "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }

DEST="${BACKUP_ROOT:-/var/backups/chengetai/dspace}"
STAMP="$(date +%Y%m%d_%H%M%S)"
ARCHIVE_DIR="$DEST/$STAMP"

log_banner "ChengetAi DSpace — Backup"
log_info "Destination: $ARCHIVE_DIR"

mkdir -p "$ARCHIVE_DIR"

# ---- 1. Database ----------------------------------------------------------- #
log_step "Backing up PostgreSQL"
backup_postgres dspace-db dspace dspace "$ARCHIVE_DIR"

# ---- 2. Assetstore --------------------------------------------------------- #
log_step "Backing up assetstore"
backup_volume dspace-backend /dspace/assetstore "$ARCHIVE_DIR" "assetstore"

# ---- 3. DSpace config ------------------------------------------------------ #
log_step "Backing up DSpace config volume"
backup_volume dspace-backend /dspace/config "$ARCHIVE_DIR" "dspace-config"

# ---- 4. engine .env -------------------------------------------------------- #
log_info "Saving .env snapshot"
cp "$ENV_FILE" "$ARCHIVE_DIR/env.snapshot"

# ---- 5. Create manifest ---------------------------------------------------- #
{
  echo "ChengetAi DSpace Backup"
  echo "Timestamp : $STAMP"
  echo "Hostname  : ${DSPACE_HOSTNAME:-unknown}"
  echo "Files:"
  ls -lh "$ARCHIVE_DIR/"
} > "$ARCHIVE_DIR/MANIFEST.txt"

# ---- 6. Prune old backups -------------------------------------------------- #
backup_prune "$DEST"

log_ok "Backup complete: $ARCHIVE_DIR"
backup_list "$DEST"
