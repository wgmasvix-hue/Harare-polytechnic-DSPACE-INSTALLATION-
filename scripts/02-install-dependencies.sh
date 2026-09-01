#!/bin/bash
# Step 2: Install all DSpace 9 dependencies
# Run as root on hrepolyREP (192.168.26.3)

set -euo pipefail

JAVA_VERSION=17
TOMCAT_VERSION=10.1.24
SOLR_VERSION=9.6.1
MAVEN_VERSION=3.9.8
PG_VERSION=15

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
die()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Detect OS
[ -f /etc/os-release ] && . /etc/os-release || die "Cannot detect OS"
log "OS: $PRETTY_NAME"

install_ubuntu_debian() {
    log "Updating package lists..."
    apt-get update -qq

    log "Installing essential tools..."
    apt-get install -y curl wget git unzip zip gnupg2 software-properties-common \
        apt-transport-https ca-certificates lsb-release

    # Java 17
    log "Installing Java $JAVA_VERSION..."
    apt-get install -y "openjdk-${JAVA_VERSION}-jdk"
    update-alternatives --set java "/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64/bin/java" 2>/dev/null || true
    export JAVA_HOME="/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-amd64"
    echo "export JAVA_HOME=$JAVA_HOME" >> /etc/environment
    echo "export PATH=\$JAVA_HOME/bin:\$PATH" >> /etc/environment

    # PostgreSQL
    log "Installing PostgreSQL $PG_VERSION..."
    # Add official PostgreSQL repo
    curl -fsSL "https://www.postgresql.org/media/keys/ACCC4CF8.asc" | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list
    apt-get update -qq
    apt-get install -y "postgresql-${PG_VERSION}" "postgresql-contrib-${PG_VERSION}"

    # Maven
    log "Installing Maven..."
    apt-get install -y maven

    # Ant (needed for DSpace installer)
    apt-get install -y ant

    # Nginx (reverse proxy)
    apt-get install -y nginx

    # UFW firewall rules
    if command -v ufw &>/dev/null; then
        ufw allow 8080/tcp  2>/dev/null || true
        ufw allow 80/tcp    2>/dev/null || true
        ufw allow 443/tcp   2>/dev/null || true
        ufw allow 8983/tcp  2>/dev/null || true
    fi
}

install_rhel_family() {
    log "Installing EPEL and tools..."
    dnf install -y epel-release curl wget git unzip zip

    # Java 17
    log "Installing Java $JAVA_VERSION..."
    dnf install -y "java-${JAVA_VERSION}-openjdk-devel"
    export JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))

    # PostgreSQL
    log "Installing PostgreSQL $PG_VERSION..."
    dnf install -y "https://download.postgresql.org/pub/repos/yum/reporpms/EL-$(rpm -E %{rhel})-x86_64/pgdg-redhat-repo-latest.noarch.rpm" 2>/dev/null || true
    dnf -qy module disable postgresql 2>/dev/null || true
    dnf install -y "postgresql${PG_VERSION}" "postgresql${PG_VERSION}-server" "postgresql${PG_VERSION}-contrib"
    "/usr/pgsql-${PG_VERSION}/bin/postgresql-${PG_VERSION}-setup" initdb
    systemctl enable --now "postgresql-${PG_VERSION}"

    # Maven
    log "Installing Maven..."
    dnf install -y maven

    # Nginx
    dnf install -y nginx

    # Firewall
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port=8080/tcp
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
    fi
}

# Route to correct installer
case "$ID" in
    ubuntu|debian) install_ubuntu_debian ;;
    rhel|centos|rocky|almalinux|fedora) install_rhel_family ;;
    *) die "Unsupported OS: $ID" ;;
esac

# ---- Install Apache Tomcat 10 ----
log "Installing Apache Tomcat $TOMCAT_VERSION..."
TOMCAT_URL="https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TOMCAT_DIR="/opt/tomcat"

# Create dspace system user
id dspace &>/dev/null || useradd -r -m -d /dspace -s /bin/bash dspace

cd /tmp
wget -q "$TOMCAT_URL" -O "tomcat.tar.gz"
mkdir -p "$TOMCAT_DIR"
tar xzf tomcat.tar.gz -C "$TOMCAT_DIR" --strip-components=1
chown -R dspace:dspace "$TOMCAT_DIR"
chmod +x "$TOMCAT_DIR"/bin/*.sh

# Tomcat systemd service
cat > /etc/systemd/system/tomcat.service <<EOF
[Unit]
Description=Apache Tomcat 10 Web Application Container
After=network.target postgresql.service

[Service]
Type=forking
User=dspace
Group=dspace
Environment="JAVA_HOME=$(java -XshowSettings:all -version 2>&1 | grep java.home | awk '{print $3}')"
Environment="CATALINA_HOME=${TOMCAT_DIR}"
Environment="CATALINA_BASE=${TOMCAT_DIR}"
Environment="CATALINA_PID=${TOMCAT_DIR}/temp/tomcat.pid"
Environment="JAVA_OPTS=-Djava.security.egd=file:/dev/./urandom -Xms512m -Xmx2g"
ExecStart=${TOMCAT_DIR}/bin/startup.sh
ExecStop=${TOMCAT_DIR}/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# ---- Install Apache Solr 9 ----
log "Installing Apache Solr $SOLR_VERSION..."
SOLR_URL="https://dlcdn.apache.org/solr/solr/${SOLR_VERSION}/solr-${SOLR_VERSION}.tgz"

cd /tmp
wget -q "$SOLR_URL" -O "solr.tgz"
tar xzf solr.tgz "solr-${SOLR_VERSION}/bin/install_solr_service.sh" --strip-components=2
bash install_solr_service.sh "solr-${SOLR_VERSION}.tgz" -f

systemctl enable solr
systemctl start solr

# ---- Enable & start PostgreSQL ----
log "Starting PostgreSQL..."
systemctl enable postgresql 2>/dev/null || systemctl enable "postgresql-${PG_VERSION}" 2>/dev/null || true
systemctl start postgresql 2>/dev/null || systemctl start "postgresql-${PG_VERSION}" 2>/dev/null || true

systemctl daemon-reload

ok "All dependencies installed successfully."
echo ""
echo "Next step: Run  scripts/03-configure-database.sh"
