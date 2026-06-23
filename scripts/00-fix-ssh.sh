#!/bin/bash
# Run this script through the Cockpit terminal at https://192.168.26.3/
# It enables SSH so you can connect remotely from any machine.

set -e

echo "=== Enabling SSH on hrepolyREP ==="

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
fi

echo "Detected OS: $OS $OS_VERSION"

# Install OpenSSH server if missing
case "$OS" in
    ubuntu|debian)
        apt-get update -qq
        apt-get install -y openssh-server
        systemctl enable ssh
        systemctl start ssh
        # Allow SSH through UFW
        if command -v ufw &>/dev/null; then
            ufw allow 22/tcp
            ufw allow OpenSSH
        fi
        ;;
    rhel|centos|rocky|almalinux|fedora)
        dnf install -y openssh-server
        systemctl enable sshd
        systemctl start sshd
        # Allow SSH through firewalld
        if command -v firewall-cmd &>/dev/null; then
            firewall-cmd --permanent --add-service=ssh
            firewall-cmd --reload
        fi
        ;;
    sles|opensuse*|suse)
        zypper install -y openssh
        systemctl enable sshd
        systemctl start sshd
        if command -v firewall-cmd &>/dev/null; then
            firewall-cmd --permanent --add-service=ssh
            firewall-cmd --reload
        fi
        ;;
    *)
        echo "Unknown OS. Attempting generic approach..."
        systemctl enable sshd 2>/dev/null || systemctl enable ssh 2>/dev/null || true
        systemctl start sshd 2>/dev/null || systemctl start ssh 2>/dev/null || true
        ;;
esac

# Verify SSH is listening
echo ""
echo "=== SSH Status ==="
systemctl status sshd 2>/dev/null || systemctl status ssh 2>/dev/null
echo ""
ss -tlnp | grep ':22' && echo "SSH is listening on port 22" || echo "WARNING: SSH not detected on port 22"

echo ""
echo "Done. You can now SSH in with: ssh root@192.168.26.3"
