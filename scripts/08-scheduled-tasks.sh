#!/bin/bash
# Step 8: Configure DSpace scheduled maintenance tasks (cron jobs)

set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
ok()  { echo -e "${GREEN}[OK]${NC} $1"; }

DSPACE_INSTALL="/dspace"

log "Configuring DSpace scheduled tasks..."

# Create cron file for dspace user
cat > /etc/cron.d/dspace <<CRONTAB
# DSpace 9 Scheduled Maintenance Tasks
# Harare Polytechnic Institutional Repository

DSPACE=${DSPACE_INSTALL}
MAILTO=dspace-admin@hrepoly.ac.zw

# Update OAI-PMH index every hour at minute 0
0 * * * * dspace \${DSPACE}/bin/dspace oai import > /dev/null 2>&1

# Run indexing/discovery update every 5 minutes
*/5 * * * * dspace \${DSPACE}/bin/dspace index-discovery -b > /dev/null 2>&1

# Harvest external content daily at 8am
0 8 * * * dspace \${DSPACE}/bin/dspace harvest -r -e dspace-admin@hrepoly.ac.zw > /dev/null 2>&1

# Send daily item subscription emails at 8am
0 8 * * * dspace \${DSPACE}/bin/dspace subscription-send -f D > /dev/null 2>&1

# Send weekly item subscription emails Sunday 9am
0 9 * * 0 dspace \${DSPACE}/bin/dspace subscription-send -f W > /dev/null 2>&1

# Clean up expired sessions daily at 2am
0 2 * * * dspace \${DSPACE}/bin/dspace cleanup -v > /dev/null 2>&1

# Generate statistics reports weekly on Sunday at 5am
0 5 * * 0 dspace \${DSPACE}/bin/dspace stat-general > /dev/null 2>&1
0 5 * * 0 dspace \${DSPACE}/bin/dspace stat-monthly > /dev/null 2>&1

# Database backup nightly at 3am
0 3 * * * root pg_dump -U dspace dspace | gzip > /var/backups/dspace/dspace-\$(date +\%Y\%m\%d).sql.gz 2>&1

# Keep only last 30 days of database backups
0 4 * * * root find /var/backups/dspace/ -name "*.sql.gz" -mtime +30 -delete
CRONTAB

# Create backup directory
mkdir -p /var/backups/dspace
chown dspace:dspace /var/backups/dspace

ok "Scheduled tasks configured in /etc/cron.d/dspace"

# ---- Create manual backup script ----
cat > /usr/local/bin/dspace-backup <<'BACKUP'
#!/bin/bash
# Manual DSpace backup script
BACKUP_DIR="/var/backups/dspace"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

echo "Backing up DSpace database..."
pg_dump -U dspace dspace | gzip > "$BACKUP_DIR/dspace-db-${DATE}.sql.gz"

echo "Backing up DSpace assets (assetstore)..."
tar czf "$BACKUP_DIR/dspace-assetstore-${DATE}.tar.gz" /dspace/assetstore/

echo "Backing up DSpace config..."
tar czf "$BACKUP_DIR/dspace-config-${DATE}.tar.gz" /dspace/config/

echo "Backup complete. Files in $BACKUP_DIR:"
ls -lh "$BACKUP_DIR/"*${DATE}*
BACKUP
chmod +x /usr/local/bin/dspace-backup

ok "Backup script created at /usr/local/bin/dspace-backup"
echo ""
echo "Run 'dspace-backup' at any time to create a manual backup."
