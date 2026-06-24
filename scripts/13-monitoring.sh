#!/bin/bash
# =================================================================
#  DSpace Health Monitoring — Harare Polytechnic
#  Checks all services every 5 minutes and sends email alerts
#  Install: bash scripts/13-monitoring.sh
# =================================================================

set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${BLUE}==>${NC} $1"; }
ok()  { echo -e "${GREEN}[DONE]${NC} $1"; }

MONITOR_SCRIPT="/usr/local/bin/dspace-monitor"
ALERT_EMAIL="${DSPACE_ALERT_EMAIL:-library@hrepoly.ac.zw}"
HOST="${DSPACE_HOSTNAME:-192.168.26.3}"

log "Installing DSpace monitoring..."

# ---- Create monitor script ----
cat > "$MONITOR_SCRIPT" <<MONITOR
#!/bin/bash
# DSpace health monitor — runs via cron
HOST="${HOST}"
ALERT_EMAIL="${ALERT_EMAIL}"
LOG="/var/log/dspace-monitor.log"
STAMP="\$(date '+%Y-%m-%d %H:%M:%S')"
FAILED=()

check_http() {
    local NAME="\$1" URL="\$2"
    CODE=\$(curl -so /dev/null -w "%{http_code}" --max-time 10 "\$URL" 2>/dev/null)
    [ "\$CODE" = "200" ] || FAILED+=("\$NAME (\$URL) returned HTTP \$CODE")
}

check_service() {
    local NAME="\$1"
    if command -v docker &>/dev/null; then
        docker inspect --format='{{.State.Status}}' "\$NAME" 2>/dev/null | grep -q "running" || \
            FAILED+=("Container \$NAME is not running")
    else
        systemctl is-active --quiet "\$NAME" 2>/dev/null || FAILED+=("Service \$NAME is not active")
    fi
}

# Check endpoints
check_http "DSpace UI"   "http://\${HOST}/"
check_http "DSpace API"  "http://\${HOST}/server/api"

# Check services
check_service "dspace-backend"
check_service "dspace-frontend"
check_service "dspace-db"
check_service "dspace-solr"
check_service "dspace-nginx"

# Disk space check
DISK_FREE=\$(df -BG / | awk 'NR==2{print \$4}' | tr -d 'G')
[ "\${DISK_FREE:-99}" -lt 3 ] && FAILED+=("Low disk space: \${DISK_FREE}GB free")

if [ \${#FAILED[@]} -gt 0 ]; then
    MSG="DSpace ALERT [\$STAMP] on \$HOST:\\n"
    for F in "\${FAILED[@]}"; do MSG+="\n  - \$F"; done
    echo -e "\$STAMP [ALERT] \${FAILED[*]}" >> "\$LOG"
    echo -e "\$MSG" | mail -s "DSpace Alert — \$HOST" "\$ALERT_EMAIL" 2>/dev/null || \
        echo -e "\$MSG" >> "\$LOG"
else
    echo "\$STAMP [OK] All services healthy" >> "\$LOG"
fi

# Keep log to last 1000 lines
tail -1000 "\$LOG" > "\$LOG.tmp" && mv "\$LOG.tmp" "\$LOG"
MONITOR

chmod +x "$MONITOR_SCRIPT"

# ---- Install cron job ----
# Run every 5 minutes
CRON_LINE="*/5 * * * * root ${MONITOR_SCRIPT}"
if ! grep -q "dspace-monitor" /etc/crontab 2>/dev/null; then
    echo "$CRON_LINE" >> /etc/crontab
fi

# ---- Create log file ----
touch /var/log/dspace-monitor.log
chmod 644 /var/log/dspace-monitor.log

ok "Monitoring installed"
echo ""
echo "  Monitor script: $MONITOR_SCRIPT"
echo "  Log file:       /var/log/dspace-monitor.log"
echo "  Alerts sent to: $ALERT_EMAIL"
echo "  Frequency:      Every 5 minutes"
echo ""
echo "  Manual check: $MONITOR_SCRIPT"
echo "  View log:     tail -f /var/log/dspace-monitor.log"
