#!/bin/bash
# Step 6: Create DSpace administrator account
# Run as root on your target host

set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
ok()  { echo -e "${GREEN}[OK]${NC} $1"; }

DSPACE_INSTALL="/dspace"

# Prompt for admin details if not set via environment
ADMIN_EMAIL="${DSPACE_ADMIN_EMAIL:-}"
ADMIN_FNAME="${DSPACE_ADMIN_FNAME:-}"
ADMIN_LNAME="${DSPACE_ADMIN_LNAME:-}"
ADMIN_PASS="${DSPACE_ADMIN_PASS:-}"

if [ -z "$ADMIN_EMAIL" ]; then
    read -rp "Admin email address: " ADMIN_EMAIL
fi
if [ -z "$ADMIN_FNAME" ]; then
    read -rp "Admin first name: " ADMIN_FNAME
fi
if [ -z "$ADMIN_LNAME" ]; then
    read -rp "Admin last name: " ADMIN_LNAME
fi
if [ -z "$ADMIN_PASS" ]; then
    read -rsp "Admin password: " ADMIN_PASS
    echo ""
fi

log "Creating DSpace administrator account..."

sudo -u dspace "$DSPACE_INSTALL/bin/dspace" create-administrator \
    -e "$ADMIN_EMAIL" \
    -f "$ADMIN_FNAME" \
    -l "$ADMIN_LNAME" \
    -p "$ADMIN_PASS" \
    -c en

ok "Administrator account created: $ADMIN_EMAIL"
echo ""
echo "Login at: http://$(hostname -I | awk '{print $1}'):4000/login"
