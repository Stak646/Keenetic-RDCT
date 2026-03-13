#!/bin/sh
# ============================================================================
# Keenetic-RDCT Installer
# https://github.com/Stak646/Keenetic-RDCT
#
# Install:  curl -fsSL https://raw.githubusercontent.com/Stak646/Keenetic-RDCT/main/scripts/install.sh | sh
#    or:    wget -qO- https://raw.githubusercontent.com/Stak646/Keenetic-RDCT/main/scripts/install.sh | sh
# ============================================================================
set -eu

# --- Config ---
REPO="Stak646/Keenetic-RDCT"
BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/$REPO/$BRANCH"
ARCHIVE_URL="https://github.com/$REPO/archive/refs/heads/${BRANCH}.tar.gz"
PREFIX="/opt/keenetic-debug"
PRODUCT="keenetic-debug"
WEBUI_PORT=""
AUTH_TOKEN=""
LAN_IP=""
ARCH=""
HAS_ENTWARE=false
HAS_PYTHON=false
DL_CMD=""
FREE_MB=0

# --- Colors (if terminal supports) ---
RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"; CYAN="\033[0;36m"; BOLD="\033[1m"; NC="\033[0m"

log()  { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
err()  { printf "${RED}[✗]${NC} %s\n" "$*" >&2; }
die()  { err "$*"; exit 1; }
line() { printf "${CYAN}────────────────────────────────────────────${NC}\n"; }

# ============================================================================
# STEP 1: Environment detection
# ============================================================================
detect_env() {
  log "Detecting environment..."

  # Architecture
  ARCH=$(uname -m 2>/dev/null || echo "unknown")
  case "$ARCH" in
    mips|mipsel|mipsle|aarch64|arm64|x86_64) ;;
    *) 
      if [ -f /proc/cpuinfo ]; then
        grep -qi 'mips' /proc/cpuinfo 2>/dev/null && ARCH="mipsel"
        grep -qi 'aarch64' /proc/cpuinfo 2>/dev/null && ARCH="aarch64"
      fi
      ;;
  esac

  # Entware
  HAS_ENTWARE=false
  if [ -d /opt/bin ] && [ -x /opt/bin/opkg ]; then
    HAS_ENTWARE=true
  fi

  # Python3 (needed for WebUI)
  HAS_PYTHON=false
  if command -v python3 >/dev/null 2>&1; then
    HAS_PYTHON=true
  fi

  # Download tool
  DL_CMD=""
  if command -v curl >/dev/null 2>&1; then
    DL_CMD="curl"
  elif command -v wget >/dev/null 2>&1; then
    DL_CMD="wget"
  else
    die "Neither curl nor wget found. Install Entware first: opkg install curl"
  fi

  # LAN IP (BusyBox-compatible — no grep -P)
  LAN_IP=""
  if command -v ip >/dev/null 2>&1; then
    LAN_IP=$(ip -4 addr show br0 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]}' || true)
    if [ -z "$LAN_IP" ]; then
      LAN_IP=$(ip -4 addr show eth0 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]}' || true)
    fi
    if [ -z "$LAN_IP" ]; then
      LAN_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' || true)
    fi
  fi
  if [ -z "$LAN_IP" ]; then
    LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "")
  fi
  [ -z "$LAN_IP" ] && LAN_IP="192.168.1.1"

  # Free disk space
  FREE_MB=0
  if command -v df >/dev/null 2>&1; then
    FREE_MB=$(df -m /opt 2>/dev/null | tail -1 | awk '{print $4}' || echo 0)
  fi

  printf "  Arch:     %s\n" "$ARCH"
  printf "  Entware:  %s\n" "$HAS_ENTWARE"
  printf "  Python3:  %s\n" "$HAS_PYTHON"
  printf "  LAN IP:   %s\n" "$LAN_IP"
  printf "  Free:     %sMB\n" "$FREE_MB"
}

# ============================================================================
# STEP 2: Install dependencies via Entware
# ============================================================================
install_deps() {
  if [ "$HAS_ENTWARE" = false ]; then
    warn "Entware not found. WebUI will not work without python3."
    warn "Install Entware first: https://github.com/Entware/Entware/wiki"
    return
  fi

  if [ "$HAS_PYTHON" = false ]; then
    log "Installing python3 (required for WebUI)..."
    log "Running opkg update..."
    opkg update 2>&1 | tail -3
    log "Installing python3 + dependencies..."
    # python3-light lacks email module needed by http.server
    # Install full python3, or light + email as fallback
    if opkg install python3 2>&1 | tail -5; then
      log "python3 installed"
    elif opkg install python3-light python3-email python3-logging python3-urllib python3-codecs 2>&1 | tail -5; then
      log "python3-light + modules installed"
    else
      warn "Could not install python3 automatically."
      warn "Try manually: opkg update && opkg install python3-light"
    fi
    # Run ldconfig to update library cache
    ldconfig 2>/dev/null || /opt/sbin/ldconfig 2>/dev/null || true
    command -v python3 >/dev/null 2>&1 && HAS_PYTHON=true
    if [ "$HAS_PYTHON" = true ]; then
      log "python3 ready: $(python3 --version 2>&1)"
    else
      warn "python3 still not found after install attempt"
    fi
  fi
}

# ============================================================================
# STEP 3: Download helper
# ============================================================================
download() {
  local url="$1" dest="$2"
  case "$DL_CMD" in
    curl) curl -fsSL --connect-timeout 15 --max-time 120 -o "$dest" "$url" ;;
    wget) wget -q --timeout=15 -O "$dest" "$url" ;;
  esac
}

# ============================================================================
# STEP 4: Download and extract project
# ============================================================================
download_project() {
  log "Downloading from GitHub..."

  local tmpdir="/tmp/rdct_install_$$"
  rm -rf "$tmpdir"
  mkdir -p "$tmpdir"

  local archive="$tmpdir/project.tar.gz"
  download "$ARCHIVE_URL" "$archive" || die "Download failed. Check internet connection."

  log "Extracting..."
  tar xzf "$archive" -C "$tmpdir" 2>/dev/null || die "Extract failed"

  # GitHub archives extract to <repo>-<branch>/ folder
  local extracted=$(ls -d "$tmpdir"/*/ 2>/dev/null | head -1)
  if [ -z "$extracted" ] || [ ! -d "$extracted" ]; then
    die "Extraction produced no directory"
  fi

  # Create install prefix
  mkdir -p "$PREFIX"

  # Copy files (preserve existing config/token/reports)
  for d in modules collectors schemas web i18n policies scripts docs examples migrations cli; do
    if [ -d "$extracted/$d" ]; then
      rm -rf "$PREFIX/$d"
      cp -r "$extracted/$d" "$PREFIX/$d"
    fi
  done

  # Copy root files
  for f in version.json LICENSE README.md PROGRESS.md DOD.md; do
    [ -f "$extracted/$f" ] && cp "$extracted/$f" "$PREFIX/$f"
  done

  # Create runtime dirs
  for d in run var tmp reports logs; do
    mkdir -p "$PREFIX/$d"
  done

  chmod -R 0755 "$PREFIX/scripts" "$PREFIX/cli" 2>/dev/null
  chmod 0700 "$PREFIX/var" "$PREFIX/run" "$PREFIX/tmp"

  rm -rf "$tmpdir"
  log "Installed to $PREFIX"
}

# ============================================================================
# STEP 5: Generate auth token
# ============================================================================
setup_token() {
  local token_file="$PREFIX/var/.auth_token"

  # Read existing token if present
  if [ -f "$token_file" ]; then
    AUTH_TOKEN=$(cat "$token_file" 2>/dev/null | tr -d '\n\r ')
  fi

  # Validate: must be non-empty and at least 16 chars
  if [ -n "$AUTH_TOKEN" ] && [ "${#AUTH_TOKEN}" -ge 16 ]; then
    log "Auth token exists (preserved)"
    return
  fi

  # Generate new token (BusyBox-compatible)
  log "Generating auth token..."
  if command -v openssl >/dev/null 2>&1; then
    AUTH_TOKEN=$(openssl rand -hex 24)
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    AUTH_TOKEN=$(cat /proc/sys/kernel/random/uuid | tr -d '-')$(cat /proc/sys/kernel/random/uuid | tr -d '-' | cut -c1-16)
  elif command -v hexdump >/dev/null 2>&1 && [ -r /dev/urandom ]; then
    AUTH_TOKEN=$(hexdump -n 24 -e '24/1 "%02x"' /dev/urandom 2>/dev/null)
  else
    AUTH_TOKEN="$(date +%s)$(cat /proc/uptime 2>/dev/null | tr -d '. ')"
  fi

  # Ensure non-empty
  if [ -z "$AUTH_TOKEN" ] || [ "${#AUTH_TOKEN}" -lt 16 ]; then
    AUTH_TOKEN="change_me_$(date +%s)"
  fi

  echo "$AUTH_TOKEN" > "$token_file"
  chmod 0600 "$token_file"
  log "Auth token generated"
}

# ============================================================================
# STEP 6: Create default config
# ============================================================================
setup_config() {
  local config="$PREFIX/config.json"

  if [ -f "$config" ]; then
    log "Config exists (preserved)"
    return
  fi

  cat > "$config" << 'CFGEOF'
{
  "config_version": 1,
  "research_mode": "medium",
  "performance_mode": "auto",
  "lang": "ru",
  "debug": false,
  "readonly": true,
  "dangerous_ops": false,
  "archive_format": "tar.gz",
  "webui": {
    "enabled": true,
    "bind": "0.0.0.0",
    "port": null,
    "port_range_start": 5000,
    "port_range_end": 5099
  },
  "governor": {
    "cpu_limit_pct": 70,
    "ram_limit_pct": 80,
    "min_disk_free_mb": 50
  }
}
CFGEOF
  chmod 0600 "$config"
  log "Config created: $config"
}

# ============================================================================
# STEP 7: Find free port
# ============================================================================
find_port() {
  local start=5000
  local end=5099
  local port="$start"

  while [ "$port" -le "$end" ]; do
    # Check if port is in use
    if command -v ss >/dev/null 2>&1; then
      if ! ss -tln 2>/dev/null | grep -q ":${port} "; then
        echo "$port"; return 0
      fi
    elif command -v netstat >/dev/null 2>&1; then
      if ! netstat -tln 2>/dev/null | grep -q ":${port} "; then
        echo "$port"; return 0
      fi
    else
      echo "$port"; return 0
    fi
    port=$((port + 1))
  done

  echo "$start"
}

# ============================================================================
# STEP 8: Start WebUI server
# ============================================================================
start_webui() {
  if [ "$HAS_PYTHON" = false ]; then
    warn "python3 not available — WebUI cannot start"
    warn "Install: opkg install python3-light"
    return 1
  fi

  # Kill old instance
  if [ -f "$PREFIX/run/webui.pid" ]; then
    local old_pid
    old_pid=$(cat "$PREFIX/run/webui.pid" 2>/dev/null || echo "")
    if [ -n "$old_pid" ]; then
      kill "$old_pid" 2>/dev/null || true
      sleep 1
    fi
  fi

  WEBUI_PORT=$(find_port)
  echo "$WEBUI_PORT" > "$PREFIX/run/webui.port"

  log "Starting WebUI on port $WEBUI_PORT..."

  # Use standalone server.py from web/server.py
  export RDCT_PORT="$WEBUI_PORT"
  export RDCT_BIND="0.0.0.0"
  export RDCT_PREFIX="$PREFIX"

  # Launch in background
  python3 "$PREFIX/web/server.py" > "$PREFIX/logs/webui.log" 2>&1 &
  local pid=$!
  echo "$pid" > "$PREFIX/run/webui.pid"

  # Wait and verify
  sleep 2
  if kill -0 "$pid" 2>/dev/null; then
    log "WebUI started (PID: $pid)"
    return 0
  else
    err "WebUI failed to start. Check: $PREFIX/logs/webui.log"
    cat "$PREFIX/logs/webui.log" 2>/dev/null | tail -5 >&2
    return 1
  fi
}

# ============================================================================
# STEP 9: Install init.d autostart
# ============================================================================
install_service() {
  local initd="/opt/etc/init.d"

  if [ ! -d "$initd" ]; then
    warn "init.d not found — no autostart"
    return
  fi

  cat > "$initd/S99keeneticrdct" << SVCEOF
#!/bin/sh
PREFIX="$PREFIX"
PIDFILE="\$PREFIX/run/webui.pid"

start() {
  if [ -f "\$PIDFILE" ]; then
    local oldpid=\$(cat "\$PIDFILE" 2>/dev/null || echo "")
    if [ -n "\$oldpid" ] && kill -0 "\$oldpid" 2>/dev/null; then
      echo "Already running (PID \$oldpid)"
      return
    fi
    rm -f "\$PIDFILE"
  fi
  echo "Starting keenetic-debug WebUI..."
  if command -v python3 >/dev/null 2>&1 && [ -f "\$PREFIX/web/server.py" ]; then
    local wport=\$(cat "\$PREFIX/run/webui.port" 2>/dev/null || echo "5000")
    RDCT_PORT=\$wport RDCT_PREFIX="\$PREFIX" RDCT_BIND="0.0.0.0" python3 "\$PREFIX/web/server.py" > "\$PREFIX/logs/webui.log" 2>&1 &
    echo "\$!" > "\$PIDFILE"
    sleep 2
    local newpid=\$(cat "\$PIDFILE" 2>/dev/null || echo "")
    if [ -n "\$newpid" ] && kill -0 "\$newpid" 2>/dev/null; then
      [ -f "\$PREFIX/run/webui.port" ] && echo "Started: http://\$(ip -4 addr show br0 2>/dev/null | awk '/inet /{split(\$2,a,"/");print a[1]}' || echo 192.168.1.1):\$(cat \$PREFIX/run/webui.port)"
    else
      echo "Failed — check \$PREFIX/logs/webui.log"
    fi
  else
    echo "python3 not found — install: opkg install python3-light"
  fi
}

stop() {
  if [ -f "\$PIDFILE" ]; then
    local pid=\$(cat "\$PIDFILE" 2>/dev/null || echo "")
    [ -n "\$pid" ] && kill "\$pid" 2>/dev/null
    rm -f "\$PIDFILE"
    echo "Stopped"
  else
    echo "Not running"
  fi
}

case "\${1:-start}" in
  start)   start ;;
  stop)    stop ;;
  restart) stop; sleep 1; start ;;
  status)
    if [ -f "\$PIDFILE" ]; then
      local spid=\$(cat "\$PIDFILE" 2>/dev/null || echo "")
      if [ -n "\$spid" ] && kill -0 "\$spid" 2>/dev/null; then
        echo "Running (PID \$spid)"
        [ -f "\$PREFIX/run/webui.port" ] && echo "Port: \$(cat \$PREFIX/run/webui.port)"
      else
        echo "Stopped (stale PID)"
        rm -f "\$PIDFILE"
      fi
    else
      echo "Stopped"
    fi
    ;;
  *) echo "Usage: \$0 {start|stop|restart|status}" ;;
esac
SVCEOF

  chmod 0755 "$initd/S99keeneticrdct"
  log "Autostart installed: $initd/S99keeneticrdct"
}

# ============================================================================
# STEP 10: Write version
# ============================================================================
write_version() {
  echo "0.1.0-alpha" > "$PREFIX/VERSION"
  cat > "$PREFIX/BUILD_INFO.json" << BEOF
{
  "version": "0.1.0-alpha",
  "arch": "$ARCH",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)",
  "entware": $HAS_ENTWARE,
  "python3": $HAS_PYTHON,
  "lan_ip": "$LAN_IP",
  "repo": "https://github.com/$REPO"
}
BEOF
}

# ============================================================================
# PRINT RESULT
# ============================================================================
print_banner() {
  local webui_ok=false
  local webui_pid=""

  if [ -f "$PREFIX/run/webui.pid" ]; then
    webui_pid=$(cat "$PREFIX/run/webui.pid" 2>/dev/null || echo "")
  fi

  if [ -n "${WEBUI_PORT:-}" ] && [ -n "$webui_pid" ] && kill -0 "$webui_pid" 2>/dev/null; then
    webui_ok=true
  fi

  echo ""
  line
  printf "${BOLD}  ✅  Keenetic-RDCT установлен!${NC}\n"
  line
  echo ""

  if [ "$webui_ok" = true ]; then
    printf "  ${BOLD}WebUI:${NC}  ${CYAN}http://%s:%s${NC}\n" "$LAN_IP" "$WEBUI_PORT"
  else
    printf "  ${YELLOW}WebUI:  не запущен (нужен python3)${NC}\n"
  fi
  echo ""
  printf "  ${BOLD}Токен:${NC}  ${GREEN}%s${NC}\n" "$AUTH_TOKEN"
  echo ""
  printf "  Откройте WebUI в браузере и используйте токен для входа.\n"

  if [ "$webui_ok" = true ]; then
    printf "  Или добавьте в URL: ${CYAN}http://%s:%s/?token=%s${NC}\n" "$LAN_IP" "$WEBUI_PORT" "$AUTH_TOKEN"
  fi

  echo ""
  line
  printf "  Prefix:    %s\n" "$PREFIX"
  printf "  Config:    %s/config.json\n" "$PREFIX"
  printf "  Token:     %s/var/.auth_token\n" "$PREFIX"
  printf "  Logs:      %s/logs/webui.log\n" "$PREFIX"
  printf "  Service:   /opt/etc/init.d/S99keeneticrdct {start|stop|status}\n"
  line
  echo ""
  printf "  CLI: ${BOLD}%s/cli/keenetic-debug --help${NC}\n" "$PREFIX"
  echo ""
}

# ============================================================================
# INTERACTIVE MENU
# ============================================================================
ask() {
  local prompt="$1" default="$2"
  printf "${CYAN}  %s${NC} [%s]: " "$prompt" "$default"
  read -r ans </dev/tty 2>/dev/null || ans=""
  echo "${ans:-$default}"
}

ask_yn() {
  local prompt="$1" default="${2:-y}"
  local ans
  ans=$(ask "$prompt (y/n)" "$default")
  case "$ans" in [yY]*) return 0 ;; *) return 1 ;; esac
}

interactive_menu() {
  echo ""
  printf "${BOLD}  Выберите режим / Choose mode:${NC}\n"
  echo ""
  echo "    1) Полная установка (рекомендуется)"
  echo "       Full install (recommended)"
  echo ""
  echo "    2) Только обновить / Update only"
  echo ""
  echo "    3) Удалить / Uninstall"
  echo ""
  echo "    4) Установить доп. приложения"
  echo "       Install extra apps"
  echo ""
  local choice
  choice=$(ask "Выбор / Choice" "1")
  echo ""

  case "$choice" in
    1) do_full_install ;;
    2) do_update ;;
    3) do_uninstall ;;
    4) do_install_apps ;;
    *) do_full_install ;;
  esac
}

do_full_install() {
  log "Полная установка / Full install..."

  install_deps
  download_project
  setup_token
  setup_config
  write_version
  install_service
  start_webui || warn "WebUI не запущен"

  # Ask about extra apps
  echo ""
  if ask_yn "Установить дополнительные приложения? / Install extra apps?"; then
    do_install_apps
  fi

  print_banner
}

do_update() {
  log "Обновление / Updating..."
  download_project
  write_version

  # Restart WebUI
  if [ -f "$PREFIX/run/webui.pid" ]; then
    local pid
    pid=$(cat "$PREFIX/run/webui.pid" 2>/dev/null || echo "")
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    sleep 1
  fi
  start_webui || warn "WebUI не запущен"
  print_banner
}

do_uninstall() {
  warn "Удаление Keenetic-RDCT / Uninstalling..."
  if ! ask_yn "Вы уверены? / Are you sure?" "n"; then
    echo "Отменено / Cancelled"
    return
  fi

  # Stop
  if [ -f "$PREFIX/run/webui.pid" ]; then
    kill "$(cat "$PREFIX/run/webui.pid" 2>/dev/null)" 2>/dev/null || true
  fi
  if [ -f /opt/etc/init.d/S99keeneticrdct ]; then
    /opt/etc/init.d/S99keeneticrdct stop 2>/dev/null || true
    rm -f /opt/etc/init.d/S99keeneticrdct
  fi
  rm -rf "$PREFIX"
  log "Удалено / Removed: $PREFIX"
}

do_install_apps() {
  echo ""
  printf "${BOLD}  Доступные приложения / Available apps:${NC}\n"
  echo ""
  echo "    1) 🛡️  NFQWS Keenetic (Anonym-tsk/nfqws-keenetic)"
  echo "    2) 🛡️  NFQWS2 Keenetic (nfqws/nfqws2-keenetic)"
  echo "    3) 🌐  NFQWS Keenetic Web (nfqws/nfqws-keenetic-web)"
  echo "    4) 🐉  HydraRoute Neo (Ground-Zerro/HydraRoute)"
  echo "    5) 🎩  MagiTrickle (MagiTrickle/MagiTrickle)"
  echo "    6) 🔐  AWG Manager (hoaxisr/awg-manager)"
  echo "    0) Пропустить / Skip"
  echo ""
  local choice
  choice=$(ask "Номер(а) через пробел / Number(s)" "0")

  for c in $choice; do
    case "$c" in
      1)
        log "Installing NFQWS Keenetic..."
        mkdir -p /opt/etc/opkg
        echo 'src/gz nfqws-keenetic https://anonym-tsk.github.io/nfqws-keenetic/all' > /opt/etc/opkg/nfqws-keenetic.conf
        opkg update 2>/dev/null; opkg install nfqws-keenetic 2>&1
        ;;
      2)
        log "Installing NFQWS2 Keenetic..."
        mkdir -p /opt/etc/opkg
        echo 'src/gz nfqws2-keenetic https://nfqws.github.io/nfqws2-keenetic/all' > /opt/etc/opkg/nfqws2-keenetic.conf
        opkg update 2>/dev/null; opkg install nfqws2-keenetic 2>&1
        ;;
      3)
        log "Installing NFQWS Keenetic Web..."
        mkdir -p /opt/etc/opkg
        echo 'src/gz nfqws-keenetic-web https://nfqws.github.io/nfqws-keenetic-web/all' > /opt/etc/opkg/nfqws-keenetic-web.conf
        opkg update 2>/dev/null; opkg install nfqws-keenetic-web 2>&1
        ;;
      4)
        log "Installing HydraRoute Neo..."
        # Check for legacy versions
        if [ -f /opt/etc/init.d/S52hydra ] || opkg status hydraroute-classic 2>/dev/null | grep -q Status; then
          warn "Обнаружена старая версия HydraRoute!"
          if ask_yn "Обновить на Neo (конфиги будут перенесены)?" "y"; then
            log "Migrating to Neo..."
          fi
        fi
        if command -v curl >/dev/null 2>&1; then
          curl -fsSL https://raw.githubusercontent.com/Ground-Zerro/HydraRoute/main/install.sh | sh
        elif command -v wget >/dev/null 2>&1; then
          wget -qO- https://raw.githubusercontent.com/Ground-Zerro/HydraRoute/main/install.sh | sh
        fi
        ;;
      5)
        # Check for HydraRoute conflict
        if ls /opt/etc/init.d/*hydra* >/dev/null 2>&1; then
          warn "⚠️  HydraRoute обнаружен! MagiTrickle может конфликтовать!"
          warn "⚠️  HydraRoute detected! MagiTrickle may conflict!"
          if ! ask_yn "Продолжить? / Continue?" "n"; then
            continue
          fi
        fi
        log "Installing MagiTrickle..."
        if command -v curl >/dev/null 2>&1; then
          curl -fsSL https://magitrickle.github.io/install.sh | sh
        fi
        ;;
      6)
        log "Installing AWG Manager..."
        if command -v curl >/dev/null 2>&1; then
          curl -fsSL https://raw.githubusercontent.com/hoaxisr/awg-manager/main/install.sh | sh
        fi
        ;;
      0|"") ;;
      *) warn "Unknown option: $c" ;;
    esac
  done
}

# ============================================================================
# MAIN
# ============================================================================
main() {
  echo ""
  line
  printf "${BOLD}  Keenetic-RDCT Installer${NC}\n"
  printf "  https://github.com/$REPO\n"
  line
  echo ""

  detect_env

  # Check disk space
  if [ "$FREE_MB" -gt 0 ] && [ "$FREE_MB" -lt 10 ]; then
    die "Not enough disk space: ${FREE_MB}MB free (need >= 10MB)"
  fi

  # Check if running interactively (stdin is a tty)
  if [ -t 0 ] 2>/dev/null; then
    interactive_menu
  else
    # Non-interactive (piped) — full install
    do_full_install
  fi
}

main "$@"
