#!/usr/bin/env bash
# =============================================================================
#  ChengetAi Deploy — Common Docker Utilities
#  Source this file in engine scripts:  source "$(dirname "$0")/../../common/docker.sh"
# =============================================================================

# Requires logging.sh to be sourced first.

# -----------------------------------------------------------------------------
# docker_require — ensure Docker and Docker Compose are installed
# -----------------------------------------------------------------------------
docker_require() {
  log_step "Checking Docker"

  if ! command -v docker &>/dev/null; then
    log_info "Docker not found — installing via get.docker.com..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    log_ok "Docker installed: $(docker --version)"
  else
    log_ok "Docker found: $(docker --version)"
  fi

  # Compose V2 (plugin)
  if ! docker compose version &>/dev/null 2>&1; then
    log_info "Docker Compose plugin not found — installing..."
    local COMPOSE_VER
    COMPOSE_VER=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
      | grep '"tag_name"' | cut -d'"' -f4)
    curl -fsSL \
      "https://github.com/docker/compose/releases/download/${COMPOSE_VER}/docker-compose-linux-x86_64" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    log_ok "Docker Compose installed: $(docker compose version)"
  else
    log_ok "Docker Compose found: $(docker compose version)"
  fi
}

# -----------------------------------------------------------------------------
# docker_network_ensure <name>
# -----------------------------------------------------------------------------
docker_network_ensure() {
  local name="$1"
  if ! docker network inspect "$name" &>/dev/null; then
    docker network create "$name"
    log_ok "Network created: $name"
  else
    log_info "Network already exists: $name"
  fi
}

# -----------------------------------------------------------------------------
# docker_compose_pull <dir>  — pull images from compose file in <dir>
# -----------------------------------------------------------------------------
docker_compose_pull() {
  local dir="${1:-.}"
  log_step "Pulling Docker images"
  docker compose -f "$dir/docker-compose.yml" --env-file "$dir/.env" pull
  log_ok "Images pulled"
}

# -----------------------------------------------------------------------------
# docker_compose_up <dir>  — start services detached
# -----------------------------------------------------------------------------
docker_compose_up() {
  local dir="${1:-.}"
  log_step "Starting services"
  docker compose -f "$dir/docker-compose.yml" --env-file "$dir/.env" up -d
  log_ok "Services started"
}

# -----------------------------------------------------------------------------
# docker_compose_down <dir>
# -----------------------------------------------------------------------------
docker_compose_down() {
  local dir="${1:-.}"
  docker compose -f "$dir/docker-compose.yml" --env-file "$dir/.env" down
}

# -----------------------------------------------------------------------------
# docker_wait_healthy <container> <timeout_seconds>
# -----------------------------------------------------------------------------
docker_wait_healthy() {
  local container="$1"
  local timeout="${2:-180}"
  local elapsed=0

  log_info "Waiting for $container to become healthy (max ${timeout}s)..."
  while true; do
    local status
    status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
    case "$status" in
      healthy)
        log_ok "$container is healthy"
        return 0
        ;;
      missing|"")
        log_error "Container $container not found"
        return 1
        ;;
    esac
    sleep 5
    elapsed=$((elapsed + 5))
    echo -n "."
    if [ "$elapsed" -ge "$timeout" ]; then
      echo ""
      log_error "$container did not become healthy within ${timeout}s"
      docker logs "$container" --tail=30 2>&1 || true
      return 1
    fi
  done
}

# -----------------------------------------------------------------------------
# docker_exec_check <container> — verify container is running
# -----------------------------------------------------------------------------
docker_exec_check() {
  local container="$1"
  docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null | grep -q "^running$"
}
