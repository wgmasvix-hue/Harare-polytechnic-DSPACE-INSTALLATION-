#!/bin/bash
# Pre-installation system check for DSpace 7.6
# Run as root on the target server

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass()  { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; ((WARN++)); }
info()  { echo -e "       $1"; }

echo "======================================================"
echo "  DSpace 7.6 Pre-Installation Check"
echo "  Server: $(hostname) / $(hostname -I | awk '{print $1}')"
echo "  Date:   $(date)"
echo "======================================================"
echo ""

# Root check
echo "--- Privileges ---"
[ "$EUID" -eq 0 ] && pass "Running as root" || fail "Must run as root (use sudo)"

# OS detection
echo ""
echo "--- Operating System ---"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    info "OS: $PRETTY_NAME"
    case "$ID" in
        ubuntu)
            VER_NUM=$(echo "$VERSION_ID" | tr -d '.')
            [ "$VER_NUM" -ge 2204 ] && pass "Ubuntu $VERSION_ID (supported)" || warn "Ubuntu $VERSION_ID - recommend 22.04 or 24.04"
            ;;
        debian)
            [ "${VERSION_ID:-0}" -ge 11 ] && pass "Debian $VERSION_ID (supported)" || warn "Debian $VERSION_ID - recommend 11 or 12"
            ;;
        rhel|centos|rocky|almalinux)
            [ "${VERSION_ID%%.*}" -ge 8 ] && pass "$NAME $VERSION_ID (supported)" || warn "$NAME $VERSION_ID - recommend 8+"
            ;;
        *)
            warn "OS '$ID' not explicitly tested. Proceeding with caution."
            ;;
    esac
fi

# CPU
echo ""
echo "--- Hardware ---"
CPU_CORES=$(nproc)
RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
DISK_FREE_GB=$(df -BG / | awk 'NR==2{print $4}' | tr -d 'G')

[ "$CPU_CORES" -ge 2 ] && pass "$CPU_CORES CPU core(s) available" || warn "Only $CPU_CORES CPU core(s) — recommend 2+"
[ "$RAM_MB" -ge 4096 ] && pass "${RAM_MB}MB RAM available" || { [ "$RAM_MB" -ge 2048 ] && warn "${RAM_MB}MB RAM — recommend 4GB+" || fail "${RAM_MB}MB RAM — minimum 2GB required"; }
[ "$DISK_FREE_GB" -ge 20 ] && pass "${DISK_FREE_GB}GB free disk space" || { [ "$DISK_FREE_GB" -ge 10 ] && warn "${DISK_FREE_GB}GB free — recommend 20GB+" || fail "${DISK_FREE_GB}GB free — minimum 10GB required"; }

# Java
echo ""
echo "--- Java ---"
if command -v java &>/dev/null; then
    JAVA_VER=$(java -version 2>&1 | head -1 | grep -oP '(?<=version ")[^"]+')
    JAVA_MAJOR=$(echo "$JAVA_VER" | grep -oP '^\d+' | head -1)
    [ "$JAVA_MAJOR" -ge 17 ] && pass "Java $JAVA_VER (JDK 17+ required)" || warn "Java $JAVA_VER — DSpace 7.6 requires Java 17"
else
    fail "Java not installed — will be installed by setup script"
fi

# Maven
echo ""
echo "--- Maven ---"
if command -v mvn &>/dev/null; then
    MVN_VER=$(mvn -v 2>&1 | head -1 | grep -oP 'Maven \K[\d.]+')
    pass "Maven $MVN_VER found"
else
    warn "Maven not installed — will be installed by setup script"
fi

# PostgreSQL
echo ""
echo "--- PostgreSQL ---"
if command -v psql &>/dev/null; then
    PG_VER=$(psql --version | grep -oP '[\d.]+' | head -1)
    pass "PostgreSQL $PG_VER found"
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        pass "PostgreSQL service is running"
    else
        warn "PostgreSQL installed but not running"
    fi
else
    warn "PostgreSQL not installed — will be installed by setup script"
fi

# Apache Tomcat / systemd
echo ""
echo "--- Tomcat ---"
if command -v catalina.sh &>/dev/null || [ -d /opt/tomcat ]; then
    pass "Tomcat found"
else
    warn "Tomcat not installed — will be installed by setup script"
fi

# Solr
echo ""
echo "--- Apache Solr ---"
if command -v solr &>/dev/null || [ -d /opt/solr ]; then
    pass "Solr found"
else
    warn "Solr not installed — will be installed by setup script"
fi

# Network
echo ""
echo "--- Network ---"
if ping -c1 -W2 8.8.8.8 &>/dev/null; then
    pass "Internet connectivity (8.8.8.8 reachable)"
else
    fail "No internet access — cannot download packages"
fi

# Ports
echo ""
echo "--- Port Availability ---"
for PORT in 8080 8009 8443 8983; do
    if ss -tlnp 2>/dev/null | grep -q ":${PORT} " || netstat -tlnp 2>/dev/null | grep -q ":${PORT} "; then
        warn "Port $PORT already in use"
    else
        pass "Port $PORT available"
    fi
done

# Summary
echo ""
echo "======================================================"
echo "  Summary: ${PASS} passed, ${WARN} warnings, ${FAIL} failed"
echo "======================================================"
if [ "$FAIL" -gt 0 ]; then
    echo "Fix the FAILED items above before running the installer."
    exit 1
else
    echo "System is ready for DSpace installation."
    exit 0
fi
