#!/bin/bash
# ============================================================
#  HARARE POLYTECHNIC DSPACE 7.6 - MASTER INSTALLER
#  Run this ONE script to install everything.
#  Must be run as root on hrepolyREP (192.168.26.3)
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${BLUE}==>${NC} $1"; }
ok()   { echo -e "${GREEN}[DONE]${NC} $1"; }
die()  { echo -e "${RED}[FATAL]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Must be root
[ "$EUID" -eq 0 ] || die "Run this script as root: sudo bash install-all.sh"

echo ""
echo "=========================================================="
echo "  HARARE POLYTECHNIC INSTITUTIONAL REPOSITORY"
echo "  DSpace 7.6 Automated Installation"
echo "  Server: $(hostname) / $(hostname -I | awk '{print $1}')"
echo "  Date:   $(date)"
echo "=========================================================="
echo ""

# Collect configuration
export DSPACE_HOSTNAME="${DSPACE_HOSTNAME:-192.168.26.3}"
export DSPACE_DB_PASSWORD="${DSPACE_DB_PASSWORD:-}"
export DSPACE_ADMIN_EMAIL="${DSPACE_ADMIN_EMAIL:-}"
export DSPACE_ADMIN_FNAME="${DSPACE_ADMIN_FNAME:-}"
export DSPACE_ADMIN_LNAME="${DSPACE_ADMIN_LNAME:-}"
export DSPACE_ADMIN_PASS="${DSPACE_ADMIN_PASS:-}"

echo "--- Configuration ---"
read -rp "Server hostname/IP [${DSPACE_HOSTNAME}]: " INPUT
[ -n "$INPUT" ] && DSPACE_HOSTNAME="$INPUT"
export DSPACE_HOSTNAME

if [ -z "$DSPACE_DB_PASSWORD" ]; then
    read -rsp "Database password for dspace user: " DSPACE_DB_PASSWORD; echo
    export DSPACE_DB_PASSWORD
fi
if [ -z "$DSPACE_ADMIN_EMAIL" ]; then
    read -rp "DSpace admin email: " DSPACE_ADMIN_EMAIL; export DSPACE_ADMIN_EMAIL
fi
if [ -z "$DSPACE_ADMIN_FNAME" ]; then
    read -rp "Admin first name: " DSPACE_ADMIN_FNAME; export DSPACE_ADMIN_FNAME
fi
if [ -z "$DSPACE_ADMIN_LNAME" ]; then
    read -rp "Admin last name: " DSPACE_ADMIN_LNAME; export DSPACE_ADMIN_LNAME
fi
if [ -z "$DSPACE_ADMIN_PASS" ]; then
    read -rsp "Admin password: " DSPACE_ADMIN_PASS; echo; export DSPACE_ADMIN_PASS
fi

echo ""
echo "Configuration summary:"
echo "  Hostname:     $DSPACE_HOSTNAME"
echo "  Admin email:  $DSPACE_ADMIN_EMAIL"
echo ""
read -rp "Proceed with installation? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

# Log to file
LOG_FILE="/tmp/dspace-install-$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
log "Full log: $LOG_FILE"

# Step 1 - Pre-check
log "Step 1/7: Running pre-installation checks..."
bash "$SCRIPT_DIR/01-precheck.sh" || { warn "Pre-check had failures. Review before continuing."; read -rp "Continue anyway? [y/N]: " C; [[ "$C" =~ ^[Yy]$ ]] || exit 1; }
ok "Pre-check complete"

# Step 2 - Dependencies
log "Step 2/7: Installing system dependencies..."
bash "$SCRIPT_DIR/02-install-dependencies.sh"
ok "Dependencies installed"

# Step 3 - Database
log "Step 3/7: Configuring PostgreSQL..."
bash "$SCRIPT_DIR/03-configure-database.sh"
ok "Database configured"

# Step 4 - DSpace backend
log "Step 4/7: Installing DSpace backend..."
bash "$SCRIPT_DIR/04-install-dspace.sh"
ok "DSpace backend installed"

# Step 5 - Angular UI
log "Step 5/7: Installing DSpace Angular UI..."
bash "$SCRIPT_DIR/05-install-angular-ui.sh"
ok "Angular UI installed"

# Step 6 - Admin account
log "Step 6/7: Creating administrator account..."
bash "$SCRIPT_DIR/06-create-admin.sh"
ok "Admin account created"

# Step 7 - Nginx + cron
log "Step 7/7: Configuring Nginx and scheduled tasks..."
bash "$SCRIPT_DIR/07-configure-nginx.sh"
bash "$SCRIPT_DIR/08-scheduled-tasks.sh"
ok "Nginx and cron configured"

echo ""
echo "=========================================================="
echo "  INSTALLATION COMPLETE!"
echo "=========================================================="
echo ""
echo "  DSpace UI:       http://${DSPACE_HOSTNAME}/"
echo "  REST API:        http://${DSPACE_HOSTNAME}/server/"
echo "  Admin login:     http://${DSPACE_HOSTNAME}/login"
echo "                   Email: ${DSPACE_ADMIN_EMAIL}"
echo ""
echo "  Solr Admin:      http://${DSPACE_HOSTNAME}/solr/"
echo "  Full log:        $LOG_FILE"
echo ""
echo "  Service commands:"
echo "    systemctl status tomcat dspace-ui solr nginx"
echo "    systemctl restart tomcat"
echo "    systemctl restart dspace-ui"
echo ""
echo "=========================================================="
