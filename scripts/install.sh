#!/usr/bin/env bash
# One-command DSpace 9.3 installer for Ubuntu-based Contabo VPS instances.
set -euo pipefail

INSTALL_DIR=/opt/dspace-install
REPO_URL=https://github.com/wgmasvix-hue/harare-polytechnic-dspace-installation-.git
BRANCH="${BRANCH:-copilot/upgrade-to-dspace-93}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
random_password() { dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 -w 0; }

[ "${EUID:-$(id -u)}" -eq 0 ] || die "Run with sudo: curl -fsSL <installer URL> | sudo bash"

export DEBIAN_FRONTEND=noninteractive
log "Installing prerequisites"
apt-get update -qq
apt-get install -y -qq ca-certificates curl git

log "Installing Docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker
docker compose version >/dev/null 2>&1 || apt-get install -y -qq docker-compose-plugin
if ! command -v caddy >/dev/null 2>&1; then
  apt-get install -y -qq caddy
fi
systemctl enable --now caddy

log "Downloading DSpace configuration"
if [ -d "$INSTALL_DIR/.git" ]; then
  git -C "$INSTALL_DIR" fetch --depth=1 origin "$BRANCH"
  git -C "$INSTALL_DIR" checkout -q FETCH_HEAD
else
  rm -rf "$INSTALL_DIR"
  git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

if [ ! -f .env ]; then
  umask 077
  SERVER_HOST="${SERVER_HOST:-BulawayoPolytechnicRepository.dare.co.zw}"
  [ -n "$SERVER_HOST" ] || die "Could not detect the public IP; rerun with SERVER_HOST=your.domain.example"
  DSPACE_DB_PASSWORD="${DSPACE_DB_PASSWORD:-$(random_password)}"
  DSPACE_ADMIN_EMAIL="${DSPACE_ADMIN_EMAIL:-admin@${SERVER_HOST}}"
  DSPACE_ADMIN_PASS="${DSPACE_ADMIN_PASS:-$(random_password)}"
  cat >.env <<EOF
SERVER_HOST=${SERVER_HOST}
DSPACE_DB_PASSWORD=${DSPACE_DB_PASSWORD}
DSPACE_ADMIN_EMAIL=${DSPACE_ADMIN_EMAIL}
DSPACE_ADMIN_PASS=${DSPACE_ADMIN_PASS}
DSPACE_SITE_NAME=${DSPACE_SITE_NAME:-Bulawayo Polytechnic Repository}
SMTP_HOST=${SMTP_HOST:-localhost}
HANDLE_PREFIX=${HANDLE_PREFIX:-123456789}
EOF
  printf '\nSave these administrator credentials securely:\n  Email: %s\n  Password: %s\n' \
    "$DSPACE_ADMIN_EMAIL" "$DSPACE_ADMIN_PASS"
fi

log "Configuring Caddy"
SERVER_HOST="$(sed -n 's/^SERVER_HOST=//p' .env | head -n 1)"
[ -n "$SERVER_HOST" ] || die ".env must contain SERVER_HOST"
mkdir -p /etc/caddy/Caddyfile.d
cat >/etc/caddy/Caddyfile.d/dspace.caddy <<EOF
${SERVER_HOST} {
    encode zstd gzip

    @dspace_api path /server /server/*
    reverse_proxy @dspace_api 127.0.0.1:8080
    reverse_proxy 127.0.0.1:4000
}
EOF
grep -qF 'import /etc/caddy/Caddyfile.d/*.caddy' /etc/caddy/Caddyfile ||
  printf '\nimport /etc/caddy/Caddyfile.d/*.caddy\n' >>/etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy

log "Validating and starting DSpace 9.3"
docker compose config --quiet
docker compose down --remove-orphans || true
docker compose pull
docker compose up -d

log "Waiting for the DSpace REST API"
for _ in $(seq 1 90); do
  if curl -fsS http://127.0.0.1:8080/server/api >/dev/null; then
    break
  fi
  sleep 10
done
curl -fsS http://127.0.0.1:8080/server/api >/dev/null ||
  die "DSpace did not start. Run: cd $INSTALL_DIR && docker compose logs dspace"

DSPACE_ADMIN_EMAIL="$(sed -n 's/^DSPACE_ADMIN_EMAIL=//p' .env | head -n 1)"
DSPACE_ADMIN_PASS="$(sed -n 's/^DSPACE_ADMIN_PASS=//p' .env | head -n 1)"
[ -n "$DSPACE_ADMIN_EMAIL" ] && [ -n "$DSPACE_ADMIN_PASS" ] ||
  die ".env must contain DSPACE_ADMIN_EMAIL and DSPACE_ADMIN_PASS"
if docker exec dspace-backend /dspace/bin/dspace create-administrator \
  -e "$DSPACE_ADMIN_EMAIL" -f Library -l Administrator -p "$DSPACE_ADMIN_PASS" -c en; then
  log "Administrator account created"
else
  printf 'Administrator account was not created (it may already exist).\n' >&2
fi

printf '\nDSpace 9.3 is available at https://%s/\n' "$SERVER_HOST"
