#!/bin/bash
# Step 3: Configure PostgreSQL for DSpace
# Run as root on hrepolyREP

set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
ok()  { echo -e "${GREEN}[OK]${NC} $1"; }

DB_NAME="dspace"
DB_USER="dspace"
# Change this password before running!
DB_PASS="${DSPACE_DB_PASSWORD:-DSpace@Hrep2024!}"

log "Configuring PostgreSQL for DSpace..."

# Ensure PostgreSQL is running
systemctl start postgresql 2>/dev/null || systemctl start "postgresql-15" 2>/dev/null || true

# Create dspace database user
log "Creating database user '$DB_USER'..."
sudo -u postgres psql -c "DROP ROLE IF EXISTS ${DB_USER};" 2>/dev/null || true
sudo -u postgres psql -c "CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASS}';"

# Create dspace database
log "Creating database '$DB_NAME'..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS ${DB_NAME};" 2>/dev/null || true
sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} WITH OWNER ${DB_USER} ENCODING 'UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8' TEMPLATE template0;"

# Enable pgcrypto extension (required by DSpace)
log "Enabling pgcrypto extension..."
sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

# Update pg_hba.conf to allow password auth from localhost
PG_HBA=$(find /etc/postgresql /var/lib/pgsql -name pg_hba.conf 2>/dev/null | head -1)
if [ -n "$PG_HBA" ]; then
    # Add dspace user local password auth if not already present
    grep -q "dspace" "$PG_HBA" || \
        sed -i "/^local.*all.*all.*peer/a local   ${DB_NAME}   ${DB_USER}   md5\nhost    ${DB_NAME}   ${DB_USER}   127.0.0.1/32   md5" "$PG_HBA"
    systemctl reload postgresql 2>/dev/null || systemctl reload "postgresql-15" 2>/dev/null || true
fi

# Test connection
log "Testing database connection..."
PGPASSWORD="$DB_PASS" psql -h localhost -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" && \
    ok "Database connection successful" || \
    echo "Connection test failed - check pg_hba.conf"

ok "PostgreSQL configured for DSpace."
echo ""
echo "Database credentials:"
echo "  Host:     localhost"
echo "  Port:     5432"
echo "  Database: $DB_NAME"
echo "  User:     $DB_USER"
echo "  Password: $DB_PASS"
echo ""
echo "Next step: Run  scripts/04-install-dspace.sh"
