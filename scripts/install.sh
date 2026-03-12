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

  # LAN IP
  LAN_IP=""
  if command -v ip >/dev/null 2>&1; then
    LAN_IP=$(ip -4 addr show br0 2>/dev/null | grep -oP 'inet \K[\d.]+' || \
             ip -4 addr show eth0 2>/dev/null | grep -oP 'inet \K[\d.]+' || \
             ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+' || \
             echo "")
  fi
  # Fallback: hostname -I or /etc/hosts
  if [ -z "$LAN_IP" ]; then
    LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "192.168.1.1")
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
    opkg update >/dev/null 2>&1
    opkg install python3-light 2>/dev/null || opkg install python3 2>/dev/null || {
      warn "Could not install python3. WebUI will not be available."
      warn "Try manually: opkg install python3-light"
    }
    command -v python3 >/dev/null 2>&1 && HAS_PYTHON=true
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

  if [ -f "$token_file" ]; then
    log "Auth token exists (preserved)"
    AUTH_TOKEN=$(cat "$token_file")
    return
  fi

  # Generate random token
  if command -v openssl >/dev/null 2>&1; then
    AUTH_TOKEN=$(openssl rand -hex 24)
  elif [ -r /dev/urandom ]; then
    AUTH_TOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
  else
    AUTH_TOKEN=$(date +%s%N 2>/dev/null || date +%s)$(head -c 8 /proc/sys/kernel/random/uuid 2>/dev/null || echo "rand")
    AUTH_TOKEN=$(echo "$AUTH_TOKEN" | md5sum 2>/dev/null | cut -c1-48 || echo "$AUTH_TOKEN")
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
  local start=5000 end=5099 port=$start

  while [ "$port" -le "$end" ]; do
    # Check if port is in use
    if command -v ss >/dev/null 2>&1; then
      ss -tln 2>/dev/null | grep -q ":${port} " || { echo "$port"; return; }
    elif command -v netstat >/dev/null 2>&1; then
      netstat -tln 2>/dev/null | grep -q ":${port} " || { echo "$port"; return; }
    else
      # No tool to check — just use start port
      echo "$port"; return
    fi
    port=$((port + 1))
  done

  echo "$start"  # fallback
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
    local old_pid=$(cat "$PREFIX/run/webui.pid")
    kill "$old_pid" 2>/dev/null
    sleep 1
  fi

  WEBUI_PORT=$(find_port)
  echo "$WEBUI_PORT" > "$PREFIX/run/webui.port"

  log "Starting WebUI on port $WEBUI_PORT..."

  # Create the WebUI server script
  cat > "$PREFIX/run/server.py" << PYEOF
import http.server, socketserver, os, json, sys, time

PORT = $WEBUI_PORT
BIND = "0.0.0.0"
PREFIX = "$PREFIX"
STATIC = os.path.join(PREFIX, "web", "static")
TOKEN_FILE = os.path.join(PREFIX, "var", ".auth_token")

def load_token():
    try:
        return open(TOKEN_FILE).read().strip()
    except:
        return ""

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=STATIC, **kw)

    def check_auth(self):
        token = load_token()
        if not token:
            return True
        auth = self.headers.get("Authorization", "")
        if auth == f"Bearer {token}":
            return True
        # Allow token in query string for browser access
        if "?" in self.path:
            qs = self.path.split("?", 1)[1]
            if f"token={token}" in qs:
                return True
        return False

    def send_json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def send_file_as_json(self, path):
        try:
            with open(path) as f:
                self.send_json(json.load(f))
        except:
            self.send_json({"error": "file not found"}, 404)

    def do_GET(self):
        path = self.path.split("?")[0]

        # Health — no auth
        if path == "/health":
            ver = "unknown"
            try: ver = open(os.path.join(PREFIX, "VERSION")).read().strip()
            except: pass
            self.send_json({"status": "ok", "version": ver, "port": PORT})
            return

        # API routes — require auth
        if path.startswith("/api/"):
            if not self.check_auth():
                self.send_json({"error": "unauthorized"}, 401)
                return

            if path == "/api/progress":
                sf = os.path.join(PREFIX, "run", "state.json")
                if os.path.exists(sf):
                    self.send_file_as_json(sf)
                else:
                    self.send_json({"state": "idle"})

            elif path == "/api/reports":
                rdir = os.path.join(PREFIX, "reports")
                reports = []
                if os.path.isdir(rdir):
                    for d in sorted(os.listdir(rdir), reverse=True):
                        dp = os.path.join(rdir, d)
                        if os.path.isdir(dp):
                            size = sum(os.path.getsize(os.path.join(dp,f)) for f in os.listdir(dp) if os.path.isfile(os.path.join(dp,f)))
                            reports.append({"id": d, "size_bytes": size})
                self.send_json({"reports": reports})

            elif path.startswith("/api/report/") and path.endswith("/manifest"):
                rid = path.split("/")[3]
                self.send_file_as_json(os.path.join(PREFIX, "reports", rid, "manifest.json"))

            elif path.startswith("/api/report/") and path.endswith("/checks"):
                rid = path.split("/")[3]
                self.send_file_as_json(os.path.join(PREFIX, "reports", rid, "checks.json"))

            elif path.startswith("/api/report/") and path.endswith("/inventory"):
                rid = path.split("/")[3]
                self.send_file_as_json(os.path.join(PREFIX, "reports", rid, "inventory.json"))

            elif path == "/api/preflight":
                self.send_json({"message": "Run: keenetic-debug preflight"})

            elif path.startswith("/api/i18n/"):
                lang = path.split("/")[-1]
                lf = os.path.join(PREFIX, "i18n", f"{lang}.json")
                if os.path.exists(lf):
                    self.send_file_as_json(lf)
                else:
                    self.send_json({})

            elif path == "/api/config":
                cf = os.path.join(PREFIX, "config.json")
                if os.path.exists(cf):
                    self.send_file_as_json(cf)
                else:
                    self.send_json({})

            elif path == "/api/device":
                info = {
                    "arch": "$(uname -m 2>/dev/null || echo unknown)",
                    "kernel": "$(uname -r 2>/dev/null || echo unknown)",
                    "hostname": "$(hostname 2>/dev/null || echo keenetic)",
                }
                self.send_json(info)

            else:
                self.send_json({"error": "not found"}, 404)
            return

        # Static files
        super().do_GET()

    def log_message(self, fmt, *args):
        pass  # Silence

print(f"WebUI listening on {BIND}:{PORT}", flush=True)
with socketserver.TCPServer((BIND, PORT), Handler) as httpd:
    httpd.serve_forever()
PYEOF

  # Launch in background
  nohup python3 "$PREFIX/run/server.py" > "$PREFIX/logs/webui.log" 2>&1 &
  local pid=$!
  echo "$pid" > "$PREFIX/run/webui.pid"

  # Wait and verify
  sleep 2
  if kill -0 "$pid" 2>/dev/null; then
    log "WebUI started (PID: $pid)"
    return 0
  else
    err "WebUI failed to start. Check: $PREFIX/logs/webui.log"
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
  if [ -f "\$PIDFILE" ] && kill -0 \$(cat "\$PIDFILE") 2>/dev/null; then
    echo "Already running"
    return
  fi
  echo "Starting keenetic-debug WebUI..."
  if command -v python3 >/dev/null 2>&1 && [ -f "\$PREFIX/run/server.py" ]; then
    nohup python3 "\$PREFIX/run/server.py" > "\$PREFIX/logs/webui.log" 2>&1 &
    echo "\$!" > "\$PIDFILE"
    sleep 1
    echo "Started"
  else
    echo "python3 not found"
  fi
}

stop() {
  if [ -f "\$PIDFILE" ]; then
    kill \$(cat "\$PIDFILE") 2>/dev/null
    rm -f "\$PIDFILE"
    echo "Stopped"
  fi
}

case "\${1:-start}" in
  start)   start ;;
  stop)    stop ;;
  restart) stop; sleep 1; start ;;
  status)
    if [ -f "\$PIDFILE" ] && kill -0 \$(cat "\$PIDFILE") 2>/dev/null; then
      echo "Running (PID \$(cat "\$PIDFILE"))"
      [ -f "\$PREFIX/run/webui.port" ] && echo "Port: \$(cat "\$PREFIX/run/webui.port")"
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
  echo ""
  line
  printf "${BOLD}  ✅  Keenetic-RDCT установлен!${NC}\n"
  line
  echo ""

  if [ -n "$WEBUI_PORT" ] && [ -f "$PREFIX/run/webui.pid" ] && kill -0 $(cat "$PREFIX/run/webui.pid") 2>/dev/null; then
    printf "  ${BOLD}WebUI:${NC}  ${CYAN}http://%s:%s${NC}\n" "$LAN_IP" "$WEBUI_PORT"
  else
    printf "  ${YELLOW}WebUI:  не запущен (нужен python3)${NC}\n"
  fi
  echo ""
  printf "  ${BOLD}Токен:${NC}  ${GREEN}%s${NC}\n" "$AUTH_TOKEN"
  echo ""
  printf "  Откройте WebUI в браузере и используйте токен для входа.\n"
  printf "  Или добавьте в URL: ${CYAN}http://%s:%s/?token=%s${NC}\n" "$LAN_IP" "$WEBUI_PORT" "$AUTH_TOKEN"
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

  install_deps
  download_project
  setup_token
  setup_config
  write_version
  install_service
  start_webui

  print_banner
}

main "$@"
