#!/usr/bin/env bash
# =============================================================================
#  ChengetAi DSpace Engine — create-site.sh
#  Creates a default community/collection structure via the DSpace REST API.
#  Usage:  bash engines/dspace-engine/scripts/create-site.sh
# =============================================================================

set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_DIR="$(cd "$ENGINE_DIR/../common" && pwd)"

source "$COMMON_DIR/logging.sh"

ENV_FILE="$ENGINE_DIR/.env"
[ -f "$ENV_FILE" ] && { set -a; source "$ENV_FILE"; set +a; }

PROTO="${PUBLIC_PROTOCOL:-http}"
BASE_URL="${PROTO}://${DSPACE_HOSTNAME:-localhost}/server"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

[ -n "$ADMIN_EMAIL" ]    || { read -rp  "Admin email: "    ADMIN_EMAIL; }
[ -n "$ADMIN_PASSWORD" ] || { read -rsp "Admin password: " ADMIN_PASSWORD; echo; }

log_banner "ChengetAi DSpace — Create Site Structure"
log_info "API: $BASE_URL"

# ---- Authenticate ---------------------------------------------------------- #
log_step "Authenticating"
LOGIN_RESPONSE=$(curl -si -X POST \
  "${BASE_URL}/api/authn/login" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "user=${ADMIN_EMAIL}&******")

TOKEN=$(echo "$LOGIN_RESPONSE" | grep -i "^Authorization:" | awk '{print $2}' | tr -d '\r')
[ -n "$TOKEN" ] || log_die "Authentication failed — check ADMIN_EMAIL and ADMIN_PASSWORD"
log_ok "Authenticated as $ADMIN_EMAIL"

# ---- Helpers --------------------------------------------------------------- #
_community() {
  local name="$1" desc="$2"
  curl -sf -X POST "${BASE_URL}/api/core/communities" \
    -H "Authorization: ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${name}\",\"metadata\":{\"dc.description.abstract\":[{\"value\":\"${desc}\",\"language\":\"en\",\"authority\":null,\"confidence\":-1,\"place\":0}]}}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])"
}

_subcommunity() {
  local parent="$1" name="$2" desc="$3"
  curl -sf -X POST "${BASE_URL}/api/core/communities?parent=${parent}" \
    -H "Authorization: ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${name}\",\"metadata\":{\"dc.description.abstract\":[{\"value\":\"${desc}\",\"language\":\"en\",\"authority\":null,\"confidence\":-1,\"place\":0}]}}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])"
}

_collection() {
  local parent="$1" name="$2" desc="$3"
  curl -sf -X POST "${BASE_URL}/api/core/collections?parent=${parent}" \
    -H "Authorization: ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${name}\",\"metadata\":{\"dc.description.abstract\":[{\"value\":\"${desc}\",\"language\":\"en\",\"authority\":null,\"confidence\":-1,\"place\":0}]}}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])" 2>/dev/null
}

# ---- Default site structure ------------------------------------------------ #
# Customise this section for your institution.

log_step "Creating community structure"

SITE_NAME="${DSPACE_NAME:-My Institutional Repository}"

# ---- Top-level: Research --------------------------------------------------- #
log_info "Creating: Research & Publications"
RESEARCH=$(_community "Research & Publications" \
  "Peer-reviewed articles, conference papers and working papers")
_collection "$RESEARCH" "Journal Articles"       "Published journal articles"
_collection "$RESEARCH" "Conference Papers"      "Conference and symposium papers"
_collection "$RESEARCH" "Working Papers"         "Pre-print and working papers"
log_ok "  Research & Publications — 3 collections"

# ---- Top-level: Theses ----------------------------------------------------- #
log_info "Creating: Theses & Dissertations"
THESES=$(_community "Theses & Dissertations" \
  "Postgraduate and undergraduate research theses")
_collection "$THESES" "Doctoral Theses"          "PhD dissertations"
_collection "$THESES" "Masters Dissertations"    "Masters level dissertations"
_collection "$THESES" "Undergraduate Projects"   "Honours and final year projects"
log_ok "  Theses & Dissertations — 3 collections"

# ---- Top-level: Library Collections --------------------------------------- #
log_info "Creating: Library Collections"
LIBRARY=$(_community "Library Collections" \
  "Curated digital library materials")
_collection "$LIBRARY" "Grey Literature"         "Reports and government documents"
_collection "$LIBRARY" "Historical Documents"    "Digitized archival materials"
_collection "$LIBRARY" "Audio-Visual Materials"  "Digitized AV educational content"
log_ok "  Library Collections — 3 collections"

# ---- Trigger re-index ------------------------------------------------------ #
log_step "Triggering Solr re-index"
docker exec dspace-backend /dspace/bin/dspace index-discovery -b &>/dev/null &
log_ok "Re-indexing started in background"

log_ok "Site structure created — visit ${PROTO}://${DSPACE_HOSTNAME}/"
