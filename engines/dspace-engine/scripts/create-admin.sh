#!/usr/bin/env bash
# =============================================================================
#  ChengetAi DSpace Engine — create-admin.sh
#  Creates or resets the DSpace administrator account.
#  Usage:  bash engines/dspace-engine/scripts/create-admin.sh
# =============================================================================

set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_DIR="$(cd "$ENGINE_DIR/../common" && pwd)"

source "$COMMON_DIR/logging.sh"

ENV_FILE="$ENGINE_DIR/.env"
[ -f "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }

# ---- Allow overrides via CLI arguments ------------------------------------- #
ADMIN_EMAIL="${1:-${ADMIN_EMAIL:-}}"
ADMIN_PASSWORD="${2:-${ADMIN_PASSWORD:-}}"

[ -n "$ADMIN_EMAIL" ]    || { read -rp    "Admin email: "    ADMIN_EMAIL; }
[ -n "$ADMIN_PASSWORD" ] || { read -rsp   "Admin password: " ADMIN_PASSWORD; echo; }

# ---- Check DSpace backend is running --------------------------------------- #
if ! docker inspect --format='{{.State.Status}}' dspace-backend 2>/dev/null | grep -q "running"; then
  log_die "dspace-backend container is not running — run install.sh first"
fi

log_banner "ChengetAi DSpace — Create Administrator"

# ---- Check if account already exists --------------------------------------- #
if docker exec dspace-backend /dspace/bin/dspace user \
    --list --email "$ADMIN_EMAIL" 2>/dev/null | grep -q "$ADMIN_EMAIL"; then
  log_warn "Account $ADMIN_EMAIL already exists"
  read -rp "Reset password? [y/N]: " RESET
  if [[ "$RESET" =~ ^[Yy]$ ]]; then
    docker exec dspace-backend /dspace/bin/dspace user \
      --modify --email "$ADMIN_EMAIL" --newpassword "$ADMIN_PASSWORD"
    log_ok "Password updated for $ADMIN_EMAIL"
  else
    log_info "No changes made"
  fi
else
  docker exec dspace-backend /dspace/bin/dspace create-administrator \
    -e "$ADMIN_EMAIL" \
    -f "Admin" \
    -l "User" \
    -p "$ADMIN_PASSWORD" \
    -c en
  log_ok "Administrator account created: $ADMIN_EMAIL"
fi
