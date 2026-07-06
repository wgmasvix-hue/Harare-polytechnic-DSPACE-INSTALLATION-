#!/usr/bin/env bash
# =============================================================================
#  ChengetAi DSpace Engine — healthcheck.sh
#  Usage:  chengetai status dspace
#          — or —
#          bash engines/dspace-engine/scripts/healthcheck.sh
# =============================================================================

set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_DIR="$(cd "$ENGINE_DIR/../common" && pwd)"

source "$COMMON_DIR/logging.sh"
source "$COMMON_DIR/healthcheck.sh"

ENV_FILE="$ENGINE_DIR/.env"
[ -f "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }

PROTO="${PUBLIC_PROTOCOL:-http}"
HOST="${DSPACE_HOSTNAME:-localhost}"

log_banner "ChengetAi DSpace — Health Status"
echo "  Host     : $HOST"
echo "  Protocol : $PROTO"
echo "  Time     : $(date)"
echo ""

# ---- Containers ------------------------------------------------------------ #
echo "Containers:"
hc_container dspace-db
hc_container dspace-solr
hc_container dspace-backend
hc_container dspace-frontend
hc_container dspace-nginx
echo ""

# ---- HTTP Endpoints -------------------------------------------------------- #
echo "Endpoints:"
hc_http "Angular UI"     "$PROTO://$HOST/"
hc_http "REST API"       "$PROTO://$HOST/server/api"
hc_http "OAI-PMH"        "$PROTO://$HOST/server/oai/request?verb=Identify"
hc_http "Solr (local)"   "http://127.0.0.1:8983/solr/"
echo ""

# ---- Database -------------------------------------------------------------- #
echo "Database:"
if docker exec dspace-db psql -U dspace dspace -c "SELECT 1;" &>/dev/null 2>&1; then
  hc_pass "PostgreSQL connection OK"
  EPERSON_COUNT=$(docker exec dspace-db psql -U dspace dspace -tAc \
    "SELECT count(*) FROM eperson;" 2>/dev/null || echo "?")
  hc_pass "Registered users: $EPERSON_COUNT"
else
  hc_fail "Cannot connect to PostgreSQL"
fi
echo ""

# ---- Disk ------------------------------------------------------------------ #
echo "Disk:"
hc_disk / 5
echo ""

# ---- Summary --------------------------------------------------------------- #
hc_summary
