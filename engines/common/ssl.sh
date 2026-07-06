#!/usr/bin/env bash
# =============================================================================
#  ChengetAi Deploy — Common SSL Utilities
#  Source this file in engine scripts:  source "$(dirname "$0")/../../common/ssl.sh"
# =============================================================================

# Requires logging.sh to be sourced first.

CERT_DIR="${CERT_DIR:-/etc/ssl/chengetai}"

# -----------------------------------------------------------------------------
# ssl_self_signed <hostname> <cert_dir>
# -----------------------------------------------------------------------------
ssl_self_signed() {
  local hostname="$1"
  local cert_dir="${2:-$CERT_DIR}"

  mkdir -p "$cert_dir"
  log_info "Generating self-signed certificate for: $hostname"

  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "$cert_dir/server.key" \
    -out    "$cert_dir/server.crt" \
    -subj "/C=ZW/ST=Harare/L=Harare/O=ChengetAi/CN=${hostname}" \
    -addext "subjectAltName=DNS:${hostname},IP:${hostname}" 2>/dev/null

  chmod 600 "$cert_dir/server.key"
  log_ok "Self-signed certificate created (valid 10 years)"
  log_warn "Browsers will show a security warning for self-signed certificates"
}

# -----------------------------------------------------------------------------
# ssl_letsencrypt <domain> <email> <nginx_container>
# -----------------------------------------------------------------------------
ssl_letsencrypt() {
  local domain="$1"
  local email="$2"
  local nginx_container="${3:-}"

  log_step "Requesting Let's Encrypt certificate for: $domain"

  # Install certbot if needed
  if ! command -v certbot &>/dev/null; then
    apt-get install -y certbot 2>/dev/null || \
      dnf install -y certbot 2>/dev/null || \
      log_die "Cannot install certbot — install it manually"
  fi

  # Stop nginx temporarily for standalone mode
  if [ -n "$nginx_container" ] && docker_exec_check "$nginx_container" 2>/dev/null; then
    log_info "Stopping $nginx_container temporarily for certbot standalone..."
    docker stop "$nginx_container"
    certbot certonly --standalone \
      --non-interactive --agree-tos \
      --email "$email" \
      -d "$domain"
    docker start "$nginx_container"
  else
    certbot certonly --standalone \
      --non-interactive --agree-tos \
      --email "$email" \
      -d "$domain"
  fi

  # Auto-renewal via cron
  if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'docker exec ${nginx_container:-nginx} nginx -s reload 2>/dev/null || true'") \
      | crontab -
    log_ok "Certbot auto-renewal cron installed"
  fi

  log_ok "Let's Encrypt certificate obtained: /etc/letsencrypt/live/$domain/"
  echo "/etc/letsencrypt/live/$domain"
}

# -----------------------------------------------------------------------------
# ssl_cert_path <domain>  — return cert dir (LE or self-signed)
# -----------------------------------------------------------------------------
ssl_cert_path() {
  local domain="$1"
  if [ -d "/etc/letsencrypt/live/$domain" ]; then
    echo "/etc/letsencrypt/live/$domain"
  else
    echo "$CERT_DIR"
  fi
}
