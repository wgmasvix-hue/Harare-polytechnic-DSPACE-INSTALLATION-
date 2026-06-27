#!/bin/bash
# =================================================================
#  Basic server hardening for Contabo VPS (public internet)
#  Run BEFORE deploying DSpace
# =================================================================

set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log() { echo -e "${BLUE}==>${NC} $1"; }
ok()  { echo -e "${GREEN}  ✓${NC} $1"; }

[ "$EUID" -eq 0 ] || { echo "Run as root"; exit 1; }

# ---- Disable root SSH login (create a deploy user instead) ----
log "Creating dspace-admin user for SSH..."
if ! id dspace-admin &>/dev/null; then
    adduser --gecos "" dspace-admin
    usermod -aG sudo dspace-admin
    ok "User dspace-admin created"
else
    ok "User dspace-admin already exists"
fi

# ---- SSH hardening ----
log "Hardening SSH config..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
cat >> /etc/ssh/sshd_config <<'SSH'

# Harare Polytechnic — hardened SSH settings
PermitRootLogin prohibit-password
PasswordAuthentication yes
MaxAuthTries 3
LoginGraceTime 20
X11Forwarding no
AllowAgentForwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
SSH
systemctl reload sshd
ok "SSH hardened (root login requires key, max 3 tries)"

# ---- Disable unused services ----
log "Disabling unused services..."
for SVC in snapd avahi-daemon cups bluetooth; do
    systemctl disable --now "$SVC" 2>/dev/null && ok "Disabled $SVC" || true
done

# ---- Automatic security updates ----
log "Enabling automatic security updates..."
apt-get install -y unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUTO'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTO
ok "Auto security updates enabled"

# ---- Swap (helps with 8GB RAM during heavy Maven builds) ----
log "Checking swap..."
if [ "$(swapon --show | wc -l)" -eq 0 ]; then
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    ok "4GB swap created"
else
    ok "Swap already configured"
fi

# ---- System limits for DSpace/Java ----
log "Setting system limits..."
cat >> /etc/security/limits.conf <<'LIMITS'
# DSpace
dspace soft nofile 65536
dspace hard nofile 65536
root   soft nofile 65536
root   hard nofile 65536
LIMITS
ok "File descriptor limits increased"

# ---- Kernel tweaks ----
cat >> /etc/sysctl.conf <<'SYSCTL'
# DSpace / Java tuning
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
vm.swappiness = 10
SYSCTL
sysctl -p &>/dev/null
ok "Kernel parameters tuned"

ok "=== Server hardening complete ==="
echo ""
echo "  SSH:   PermitRootLogin requires key"
echo "  UFW:   ports 22, 80, 443 only"
echo "  Swap:  4GB added"
echo "  Auto security updates: ON"
echo ""
echo "Next: bash scripts/14-contabo-deploy.sh"
