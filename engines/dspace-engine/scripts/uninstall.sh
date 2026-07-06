#!/usr/bin/env bash
# =============================================================================
#  ChengetAi DSpace Engine — uninstall.sh
#  Usage:  chengetai uninstall dspace
#          — or —
#          bash engines/dspace-engine/scripts/uninstall.sh [--purge]
#
#  Without --purge: stops and removes containers; keeps volumes (data safe)
#  With    --purge: removes containers AND all volumes (DESTRUCTIVE)
# =============================================================================

set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_DIR="$(cd "$ENGINE_DIR/../common" && pwd)"

source "$COMMON_DIR/logging.sh"

ENV_FILE="$ENGINE_DIR/.env"
[ -f "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }

PURGE="${1:-}"

log_banner "ChengetAi DSpace — Uninstall"

if [ "$PURGE" = "--purge" ]; then
  echo -e "${C_RED}WARNING: --purge will permanently delete ALL data including the database and assetstore.${C_RESET}"
  read -rp "Type PURGE to confirm: " CONFIRM
  [ "$CONFIRM" = "PURGE" ] || { log_info "Uninstall cancelled"; exit 0; }
else
  log_info "Containers will be removed. Volumes (data) will be PRESERVED."
  log_info "Use --purge to also delete all data."
  read -rp "Continue? [y/N]: " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { log_info "Uninstall cancelled"; exit 0; }
fi

# ---- Backup before uninstall (soft mode only) ------------------------------ #
if [ "$PURGE" != "--purge" ]; then
  log_step "Creating backup before uninstall"
  bash "$ENGINE_DIR/scripts/backup.sh" || log_warn "Backup failed — continuing anyway"
fi

# ---- Remove containers ----------------------------------------------------- #
log_step "Stopping and removing containers"
if [ "$PURGE" = "--purge" ]; then
  docker compose -f "$ENGINE_DIR/docker-compose.yml" --env-file "$ENV_FILE" \
    down -v --remove-orphans
  log_ok "Containers and volumes removed"
else
  docker compose -f "$ENGINE_DIR/docker-compose.yml" --env-file "$ENV_FILE" \
    down --remove-orphans
  log_ok "Containers removed (volumes preserved)"
  log_info "To restore: run install.sh — existing data will be picked up automatically"
fi

# ---- Remove cron jobs ------------------------------------------------------ #
if crontab -l 2>/dev/null | grep -q "dspace"; then
  crontab -l 2>/dev/null | grep -v "dspace" | crontab -
  log_ok "DSpace cron jobs removed"
fi

log_ok "Uninstall complete"
