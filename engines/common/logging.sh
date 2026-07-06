#!/usr/bin/env bash
# =============================================================================
#  ChengetAi Deploy — Common Logging Library
#  Source this file in engine scripts:  source "$(dirname "$0")/../../common/logging.sh"
# =============================================================================

# Colours — disabled automatically when not a terminal
if [ -t 1 ]; then
  C_RED='\033[0;31m'
  C_GREEN='\033[0;32m'
  C_YELLOW='\033[1;33m'
  C_BLUE='\033[0;34m'
  C_CYAN='\033[0;36m'
  C_BOLD='\033[1m'
  C_RESET='\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''; C_BOLD=''; C_RESET=''
fi

# Log file (override by setting CHENGETAI_LOG before sourcing)
CHENGETAI_LOG="${CHENGETAI_LOG:-/var/log/chengetai/deploy.log}"

_log_write() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  # Always write to log file if writable
  if mkdir -p "$(dirname "$CHENGETAI_LOG")" 2>/dev/null && \
     touch "$CHENGETAI_LOG" 2>/dev/null; then
    echo "[$ts] [$level] $msg" >> "$CHENGETAI_LOG"
  fi
}

log_info()    { echo -e "${C_BLUE}==>${C_RESET} $*";                _log_write INFO    "$*"; }
log_ok()      { echo -e "${C_GREEN}[OK]${C_RESET} $*";              _log_write OK      "$*"; }
log_warn()    { echo -e "${C_YELLOW}[WARN]${C_RESET} $*";           _log_write WARN    "$*"; }
log_error()   { echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2;         _log_write ERROR   "$*"; }
log_step()    { echo -e "\n${C_BOLD}${C_CYAN}▶ $*${C_RESET}";       _log_write STEP    "$*"; }
log_die()     { log_error "$*"; exit 1; }

# Print a banner
log_banner() {
  local title="$1"
  local width=60
  echo ""
  echo -e "${C_BOLD}$(printf '=%.0s' $(seq 1 $width))${C_RESET}"
  printf "${C_BOLD}  %-$((width-4))s  ${C_RESET}\n" "$title"
  echo -e "${C_BOLD}$(printf '=%.0s' $(seq 1 $width))${C_RESET}"
  echo ""
}
