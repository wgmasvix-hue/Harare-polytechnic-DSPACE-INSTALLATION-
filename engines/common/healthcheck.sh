#!/usr/bin/env bash
# =============================================================================
#  ChengetAi Deploy — Common Health-Check Utilities
#  Source this file in engine scripts:  source "$(dirname "$0")/../../common/healthcheck.sh"
# =============================================================================

# Requires logging.sh to be sourced first.

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

hc_pass() { echo -e "  ${C_GREEN}[PASS]${C_RESET} $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
hc_warn() { echo -e "  ${C_YELLOW}[WARN]${C_RESET} $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
hc_fail() { echo -e "  ${C_RED}[FAIL]${C_RESET} $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# -----------------------------------------------------------------------------
# hc_http <label> <url> [expected_code]
# -----------------------------------------------------------------------------
hc_http() {
  local label="$1"
  local url="$2"
  local expected="${3:-200}"

  local code
  code=$(curl -so /dev/null -w "%{http_code}" --max-time 15 "$url" 2>/dev/null)

  if [ "$code" = "$expected" ]; then
    hc_pass "$label → $url (HTTP $code)"
  else
    hc_fail "$label → $url (HTTP $code, expected $expected)"
  fi
}

# -----------------------------------------------------------------------------
# hc_container <container_name>
# -----------------------------------------------------------------------------
hc_container() {
  local name="$1"
  local status
  status=$(docker inspect --format='{{.State.Status}}' "$name" 2>/dev/null || echo "not_found")
  if [ "$status" = "running" ]; then
    local health
    health=$(docker inspect --format='{{.State.Health.Status}}' "$name" 2>/dev/null || echo "")
    if [ -n "$health" ] && [ "$health" != "healthy" ]; then
      hc_warn "Container $name: running but health=$health"
    else
      hc_pass "Container $name: $status"
    fi
  else
    hc_fail "Container $name: $status"
  fi
}

# -----------------------------------------------------------------------------
# hc_disk <path> <min_gb>
# -----------------------------------------------------------------------------
hc_disk() {
  local path="${1:-/}"
  local min_gb="${2:-5}"
  local free_gb
  free_gb=$(df -BG "$path" 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G')
  if [ "${free_gb:-0}" -ge "$min_gb" ]; then
    hc_pass "Disk ($path): ${free_gb}GB free"
  else
    hc_warn "Disk ($path): only ${free_gb}GB free (recommend >=${min_gb}GB)"
  fi
}

# -----------------------------------------------------------------------------
# hc_summary — print result counts and exit 1 if any failures
# -----------------------------------------------------------------------------
hc_summary() {
  echo ""
  echo "────────────────────────────────────────"
  printf "  ${C_GREEN}%d passed${C_RESET}  ${C_YELLOW}%d warnings${C_RESET}  ${C_RED}%d failed${C_RESET}\n" \
    "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
  echo "────────────────────────────────────────"
  if [ "$FAIL_COUNT" -gt 0 ]; then
    log_error "Health check failed — review the items above"
    return 1
  fi
  log_ok "All checks passed"
  return 0
}
