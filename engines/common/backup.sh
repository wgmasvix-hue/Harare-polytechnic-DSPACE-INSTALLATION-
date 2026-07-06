#!/usr/bin/env bash
# =============================================================================
#  ChengetAi Deploy — Common Backup Utilities
#  Source this file in engine scripts:  source "$(dirname "$0")/../../common/backup.sh"
# =============================================================================

# Requires logging.sh to be sourced first.

BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/chengetai}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# -----------------------------------------------------------------------------
# backup_postgres <container> <db_user> <db_name> <dest_dir> — dump via Docker
# -----------------------------------------------------------------------------
backup_postgres() {
  local container="$1"
  local db_user="$2"
  local db_name="$3"
  local dest_dir="$4"
  local stamp
  stamp="$(date +%Y%m%d_%H%M%S)"

  mkdir -p "$dest_dir"
  local file="$dest_dir/${db_name}-${stamp}.sql.gz"

  log_info "Dumping PostgreSQL database: $db_name → $file"
  docker exec "$container" \
    pg_dump -U "$db_user" "$db_name" | gzip > "$file"
  log_ok "Database backup saved: $file"
  echo "$file"
}

# -----------------------------------------------------------------------------
# backup_volume <container> <volume_path> <dest_dir> <label>
# -----------------------------------------------------------------------------
backup_volume() {
  local container="$1"
  local volume_path="$2"
  local dest_dir="$3"
  local label="$4"
  local stamp
  stamp="$(date +%Y%m%d_%H%M%S)"

  mkdir -p "$dest_dir"
  local file="$dest_dir/${label}-${stamp}.tar.gz"

  log_info "Archiving $volume_path → $file"
  docker run --rm \
    --volumes-from "$container" \
    -v "$dest_dir":/backup \
    alpine \
    tar czf "/backup/$(basename "$file")" -C "$volume_path" .
  log_ok "Volume backup saved: $file"
  echo "$file"
}

# -----------------------------------------------------------------------------
# backup_prune <dir> — remove backups older than BACKUP_RETENTION_DAYS
# -----------------------------------------------------------------------------
backup_prune() {
  local dir="$1"
  log_info "Pruning backups older than ${BACKUP_RETENTION_DAYS} days in $dir"
  find "$dir" -name "*.sql.gz" -o -name "*.tar.gz" | \
    xargs -I{} find {} -mtime "+${BACKUP_RETENTION_DAYS}" -delete 2>/dev/null || true
  log_ok "Backup pruning complete"
}

# -----------------------------------------------------------------------------
# backup_list <dir> — list available backups
# -----------------------------------------------------------------------------
backup_list() {
  local dir="$1"
  if [ -d "$dir" ]; then
    echo ""
    echo "Available backups in $dir:"
    ls -lhtr "$dir"/*.sql.gz "$dir"/*.tar.gz 2>/dev/null || echo "  (none found)"
    echo ""
  else
    log_warn "Backup directory not found: $dir"
  fi
}

# -----------------------------------------------------------------------------
# restore_postgres <container> <db_user> <db_name> <file>
# -----------------------------------------------------------------------------
restore_postgres() {
  local container="$1"
  local db_user="$2"
  local db_name="$3"
  local file="$4"

  [ -f "$file" ] || log_die "Backup file not found: $file"

  log_info "Restoring database $db_name from $file"
  gunzip -c "$file" | docker exec -i "$container" \
    psql -U "$db_user" "$db_name"
  log_ok "Database restored"
}
