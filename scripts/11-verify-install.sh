#!/bin/bash
# Verify DSpace installation is fully working
# Run after installation is complete

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0; WARN=0
pass()  { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
info()  { echo -e "       $1"; }

HOST="${1:-192.168.26.3}"

echo "======================================================"
echo "  DSpace 7.6 — Installation Verification"
echo "  Testing: http://${HOST}"
echo "  Date: $(date)"
echo "======================================================"
echo ""

# ---- Services ----
echo "--- Services ---"
if command -v docker &>/dev/null && docker compose ps 2>/dev/null | grep -q "Up"; then
    # Docker mode
    for SVC in dspace-db dspace-solr dspace-backend dspace-frontend dspace-nginx; do
        STATUS=$(docker inspect --format='{{.State.Status}}' "$SVC" 2>/dev/null || echo "not found")
        [ "$STATUS" = "running" ] && pass "$SVC: running" || fail "$SVC: $STATUS"
    done
else
    # Native mode
    for SVC in postgresql tomcat solr dspace-ui nginx; do
        systemctl is-active --quiet "$SVC" 2>/dev/null && pass "$SVC running" || warn "$SVC not found/stopped"
    done
fi

# ---- HTTP Endpoints ----
echo ""
echo "--- HTTP Endpoints ---"

# Frontend
HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" --max-time 10 "http://${HOST}/" 2>/dev/null)
[ "$HTTP_CODE" = "200" ] && pass "Frontend UI (http://${HOST}/): HTTP $HTTP_CODE" || fail "Frontend: HTTP $HTTP_CODE"

# REST API
HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" --max-time 10 "http://${HOST}/server/api" 2>/dev/null)
[ "$HTTP_CODE" = "200" ] && pass "REST API (http://${HOST}/server/api): HTTP $HTTP_CODE" || fail "REST API: HTTP $HTTP_CODE"

# OAI-PMH
HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" --max-time 10 "http://${HOST}/server/oai/request?verb=Identify" 2>/dev/null)
[ "$HTTP_CODE" = "200" ] && pass "OAI-PMH endpoint: HTTP $HTTP_CODE" || warn "OAI-PMH: HTTP $HTTP_CODE (may need indexing)"

# Solr (internal)
HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" --max-time 5 "http://localhost:8983/solr/" 2>/dev/null)
[ "$HTTP_CODE" = "200" ] && pass "Solr admin (localhost:8983): HTTP $HTTP_CODE" || warn "Solr: HTTP $HTTP_CODE"

# ---- REST API Content ----
echo ""
echo "--- REST API ---"
API_RESPONSE=$(curl -sf --max-time 10 "http://${HOST}/server/api" 2>/dev/null)
if echo "$API_RESPONSE" | grep -q "dspaceVersion"; then
    DSPACE_VER=$(echo "$API_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('dspaceVersion','unknown'))" 2>/dev/null || echo "7.x")
    pass "DSpace version: $DSPACE_VER"
    COMM_COUNT=$(curl -sf "http://${HOST}/server/api/core/communities?size=1" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('page',{}).get('totalElements',0))" 2>/dev/null || echo "?")
    COLL_COUNT=$(curl -sf "http://${HOST}/server/api/core/collections?size=1" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('page',{}).get('totalElements',0))" 2>/dev/null || echo "?")
    info "Communities: $COMM_COUNT | Collections: $COLL_COUNT"
    [ "$COMM_COUNT" -gt 0 ] 2>/dev/null && pass "Repository structure present ($COMM_COUNT communities)" || warn "No communities yet — run scripts/10-setup-collections.sh"
else
    fail "REST API not returning expected response"
fi

# ---- Database ----
echo ""
echo "--- Database ---"
if command -v psql &>/dev/null; then
    PGPASSWORD="${DSPACE_DB_PASSWORD:-DSpaceHrep2024!}" psql -h localhost -U dspace -d dspace \
        -c "SELECT count(*) FROM eperson;" &>/dev/null && pass "Database connection OK" || fail "Cannot connect to database"
elif docker exec dspace-db psql -U dspace -d dspace -c "SELECT 1;" &>/dev/null 2>&1; then
    pass "Database connection OK (Docker)"
else
    warn "Could not verify database directly"
fi

# ---- Disk Space ----
echo ""
echo "--- Disk Space ---"
DISK_FREE=$(df -BG /dspace 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || df -BG / | awk 'NR==2{print $4}' | tr -d 'G')
[ "${DISK_FREE:-0}" -gt 5 ] && pass "${DISK_FREE}GB free disk space" || warn "Low disk: ${DISK_FREE}GB free"

# ---- Summary ----
echo ""
echo "======================================================"
echo "  ${PASS} passed | ${WARN} warnings | ${FAIL} failed"
echo "======================================================"
[ "$FAIL" -gt 0 ] && echo "Action required — see FAIL items above." || echo "Installation looks healthy!"

echo ""
echo "Access your repository:"
echo "  http://${HOST}/"
echo "  http://${HOST}/login  (admin)"
