#!/bin/bash
# =================================================================
#  DSpace Community & Collection Setup — Harare Polytechnic
#  Creates the full repository structure via REST API
#  Run AFTER DSpace is up and admin account is created
# =================================================================

set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${BLUE}==>${NC} $1"; }
ok()   { echo -e "${GREEN}[DONE]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Load config from .env if available
[ -f "$(dirname $0)/../.env" ] && source "$(dirname $0)/../.env"

BASE_URL="${DSPACE_SERVER_URL:-http://192.168.26.3/server}"
ADMIN_EMAIL="${DSPACE_ADMIN_EMAIL:-library@hrepoly.ac.zw}"
ADMIN_PASS="${DSPACE_ADMIN_PASS:-}"

if [ -z "$ADMIN_PASS" ]; then
    read -rsp "DSpace admin password for ${ADMIN_EMAIL}: " ADMIN_PASS; echo
fi

log "Connecting to DSpace at: $BASE_URL"
log "Logging in as: $ADMIN_EMAIL"

# ---- Authenticate ----
LOGIN_RESPONSE=$(curl -si -X POST \
    "${BASE_URL}/api/authn/login" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "user=${ADMIN_EMAIL}&password=${ADMIN_PASS}")

TOKEN=$(echo "$LOGIN_RESPONSE" | grep -i "Authorization:" | awk '{print $2}' | tr -d '\r')
[ -z "$TOKEN" ] && { warn "Authentication failed. Check credentials."; exit 1; }
ok "Authenticated"

# Helper: create a top-level community
create_community() {
    local NAME="$1"
    local SHORT_DESC="$2"
    curl -sf -X POST \
        "${BASE_URL}/api/core/communities" \
        -H "Authorization: ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"${NAME}\",\"metadata\":{\"dc.description.abstract\":[{\"value\":\"${SHORT_DESC}\",\"language\":\"en\",\"authority\":null,\"confidence\":-1,\"place\":0}]}}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])"
}

# Helper: create a subcommunity
create_subcommunity() {
    local PARENT_UUID="$1"
    local NAME="$2"
    local SHORT_DESC="$3"
    curl -sf -X POST \
        "${BASE_URL}/api/core/communities?parent=${PARENT_UUID}" \
        -H "Authorization: ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"${NAME}\",\"metadata\":{\"dc.description.abstract\":[{\"value\":\"${SHORT_DESC}\",\"language\":\"en\",\"authority\":null,\"confidence\":-1,\"place\":0}]}}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])"
}

# Helper: create a collection inside a community
create_collection() {
    local PARENT_UUID="$1"
    local NAME="$2"
    local SHORT_DESC="$3"
    curl -sf -X POST \
        "${BASE_URL}/api/core/collections?parent=${PARENT_UUID}" \
        -H "Authorization: ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"${NAME}\",\"metadata\":{\"dc.description.abstract\":[{\"value\":\"${SHORT_DESC}\",\"language\":\"en\",\"authority\":null,\"confidence\":-1,\"place\":0}]}}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])" 2>/dev/null
}

# ================================================================
#  HARARE POLYTECHNIC REPOSITORY STRUCTURE
# ================================================================

log "Creating Harare Polytechnic repository structure..."

# ---- 1. ACADEMIC DEPARTMENTS ----
log "Creating: Academic Departments"
ACADEMIC=$(create_community "Academic Departments" \
    "Research and academic works by Harare Polytechnic departments")

    # Engineering
    ENG=$(create_subcommunity "$ACADEMIC" "Faculty of Engineering" \
        "Civil, Mechanical, Electrical and Chemical Engineering works")
    create_collection "$ENG" "Final Year Projects — Engineering" "Undergraduate final year project reports"
    create_collection "$ENG" "Theses and Dissertations — Engineering" "Postgraduate research theses"
    create_collection "$ENG" "Research Papers — Engineering" "Peer-reviewed and conference papers"
    ok "  Faculty of Engineering done"

    # ICT & Electronics
    ICT=$(create_subcommunity "$ACADEMIC" "Faculty of ICT & Electronics" \
        "Information Technology, Computer Science and Electronics works")
    create_collection "$ICT" "Final Year Projects — ICT" "ICT undergraduate final year projects"
    create_collection "$ICT" "Theses and Dissertations — ICT" "ICT postgraduate research"
    create_collection "$ICT" "Software Projects & Source Code" "Documented software development projects"
    ok "  Faculty of ICT & Electronics done"

    # Business
    BUS=$(create_subcommunity "$ACADEMIC" "Faculty of Business Management" \
        "Business, Accounting, Marketing and Management works")
    create_collection "$BUS" "Final Year Projects — Business" "Business undergraduate projects"
    create_collection "$BUS" "Theses and Dissertations — Business" "Business postgraduate research"
    create_collection "$BUS" "Case Studies" "Business case studies and analysis"
    ok "  Faculty of Business Management done"

    # Applied Sciences
    SCI=$(create_subcommunity "$ACADEMIC" "Faculty of Applied Sciences" \
        "Science, Mathematics, and Applied Sciences works")
    create_collection "$SCI" "Final Year Projects — Sciences" "Science undergraduate projects"
    create_collection "$SCI" "Research Papers — Sciences" "Science research and publications"
    ok "  Faculty of Applied Sciences done"

    # Fashion & Textiles
    FAT=$(create_subcommunity "$ACADEMIC" "Faculty of Fashion & Textiles" \
        "Fashion design, textiles and clothing technology")
    create_collection "$FAT" "Final Year Projects — Fashion" "Fashion and textiles undergraduate projects"
    create_collection "$FAT" "Design Portfolios" "Fashion and textile design portfolios"
    ok "  Faculty of Fashion & Textiles done"

    # Built Environment
    BE=$(create_subcommunity "$ACADEMIC" "Faculty of Built Environment" \
        "Architecture, Construction, Quantity Surveying and Urban Planning")
    create_collection "$BE" "Final Year Projects — Built Environment" "Built environment undergraduate projects"
    create_collection "$BE" "Theses — Built Environment" "Postgraduate research"
    ok "  Faculty of Built Environment done"

ok "Academic Departments structure created"

# ---- 2. RESEARCH & INNOVATION ----
log "Creating: Research & Innovation Hub"
RESEARCH=$(create_community "Research & Innovation Hub" \
    "Harare Polytechnic research outputs and innovation projects")
create_collection "$RESEARCH" "Staff Research Publications" "Research papers and journal articles by HP staff"
create_collection "$RESEARCH" "Conference Proceedings" "Papers presented at local and international conferences"
create_collection "$RESEARCH" "Innovation & Patents" "Innovation projects and patent documentation"
create_collection "$RESEARCH" "Industry Collaboration Reports" "Reports from industry partnership projects"
ok "Research & Innovation Hub done"

# ---- 3. LIBRARY COLLECTIONS ----
log "Creating: Library Collections"
LIBRARY=$(create_community "Library Collections" \
    "Curated collections managed by the HP Library")
create_collection "$LIBRARY" "Local Newspapers & Periodicals" "Zimbabwe newspapers and magazines"
create_collection "$LIBRARY" "Zimbabwe Grey Literature" "Reports, working papers, government documents"
create_collection "$LIBRARY" "Historical Documents" "Historical records relating to Harare Polytechnic"
create_collection "$LIBRARY" "Audio-Visual Materials" "Digitized audio and video educational materials"
ok "Library Collections done"

# ---- 4. STUDENT WORKS ----
log "Creating: Student Works"
STUDENTS=$(create_community "Student Works" \
    "Outstanding student work approved for the repository")
create_collection "$STUDENTS" "Award-Winning Projects" "Prize-winning student projects"
create_collection "$STUDENTS" "Student Exhibitions" "Works from annual student exhibitions"
ok "Student Works done"

# ---- Final index ----
log "Re-running Solr index to register new communities..."
if command -v docker &>/dev/null && docker ps | grep -q dspace-backend; then
    docker exec dspace-backend /dspace/bin/dspace index-discovery -b &>/dev/null &
elif [ -f /dspace/bin/dspace ]; then
    sudo -u dspace /dspace/bin/dspace index-discovery -b &>/dev/null &
fi

ok "=== Repository structure complete! ==="
echo ""
echo "Created communities:"
echo "  1. Academic Departments"
echo "     ├── Faculty of Engineering        (3 collections)"
echo "     ├── Faculty of ICT & Electronics  (3 collections)"
echo "     ├── Faculty of Business Mgmt      (3 collections)"
echo "     ├── Faculty of Applied Sciences   (2 collections)"
echo "     ├── Faculty of Fashion & Textiles (2 collections)"
echo "     └── Faculty of Built Environment  (2 collections)"
echo "  2. Research & Innovation Hub         (4 collections)"
echo "  3. Library Collections               (4 collections)"
echo "  4. Student Works                     (2 collections)"
echo ""
echo "Login to http://${BASE_URL%/server} to see your repository."
