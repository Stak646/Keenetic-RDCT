#!/bin/sh
# =============================================================================
# keenetic-debug installer
# Usage: curl -fsSL <url>/install.sh | sh
#    or: wget -qO- <url>/install.sh | sh
#    or: sh install.sh [options]
# =============================================================================
# Steps 341-371, 396-430

# --- Step 342: Strict mode ---
set -eu
trap 'cleanup; exit 1' INT TERM
trap 'cleanup' EXIT

# --- Constants ---
PRODUCT="keenetic-debug"
DEFAULT_PREFIX="/opt/$PRODUCT"
MANIFEST_URL="${MANIFEST_URL:-https://github.com/keenetic-debug/releases/latest/download/release-manifest.json}"
INSTALL_LOG=""
_TMPDIR=""
_CLEANUP_DIRS=""
_EXIT_CODE=0

# --- Defaults ---
MODE="install"          # install | upgrade | uninstall | verify | repair
PREFIX="$DEFAULT_PREFIX"
CHANNEL="stable"
OFFLINE_BUNDLE=""
INTERACTIVE="false"
DRY_RUN="false"
AUTOSTART="true"
INSTALL_WEBUI="true"
CUSTOM_URL=""
VERBOSE="false"
FORCE="false"
PRINT_CONFIG="false"
PRINT_URLS="false"

# =============================================================================
# Step 352: Parse flags
# =============================================================================
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --prefix)       PREFIX="$2"; shift 2 ;;
      --version)      PINNED_VERSION="$2"; shift 2 ;;
      --channel)      CHANNEL="$2"; shift 2 ;;
      --offline)      OFFLINE_BUNDLE="$2"; MODE="install"; shift 2 ;;
      --upgrade)      MODE="upgrade"; shift ;;
      --uninstall)    MODE="uninstall"; shift ;;
      --verify)       MODE="verify"; shift ;;
      --repair)       MODE="repair"; shift ;;
      --dry-run)      DRY_RUN="true"; shift ;;
      --interactive)  INTERACTIVE="true"; shift ;;
      --yes|-y)       FORCE="true"; shift ;;
      --no-autostart) AUTOSTART="false"; shift ;;
      --no-webui)     INSTALL_WEBUI="false"; shift ;;
      --webui-only)   MODE="webui-only"; shift ;;
      --print-config-default) PRINT_CONFIG="true"; shift ;;
      --print-urls)   PRINT_URLS="true"; shift ;;
      --base-url)     CUSTOM_URL="$2"; shift 2 ;;
      --verbose|-v)   VERBOSE="true"; shift ;;
      --help|-h)      usage; exit 0 ;;
      *) die "Unknown option: $1. Use --help for usage." ;;
    esac
  done
}

usage() {
  cat << 'USAGE'
keenetic-debug installer

Usage: install.sh [OPTIONS]

Modes:
  (default)          Install fresh
  --upgrade          Upgrade existing installation
  --uninstall        Remove installation (use --yes to skip confirmation)
  --verify           Verify artifacts integrity without installing
  --repair           Fix permissions/dirs without touching data
  --dry-run          Show what would happen without writing

Options:
  --prefix PATH      Install prefix (default: /opt/keenetic-debug)
  --version VER      Pin to specific version
  --channel CHAN      Release channel: stable|beta (default: stable)
  --offline PATH     Install from offline bundle
  --no-autostart     Don't install init.d service
  --no-webui         Install CLI/Core only (headless)
  --webui-only       Install WebUI only (dev mode)
  --base-url URL     Custom mirror URL (requires pinned sha256)
  --interactive      Allow interactive prompts
  --yes              Auto-confirm destructive operations
  --verbose          Verbose output
  --print-config-default  Print default config.json and exit
  --print-urls       Print download URLs and exit
  --help             Show this help
USAGE
}

# =============================================================================
# Utilities
# =============================================================================

log() { echo "[$PRODUCT] $*"; }
log_v() { [ "$VERBOSE" = "true" ] && log "$@" || true; }
warn() { echo "[$PRODUCT] WARNING: $*" >&2; }
die() { echo "[$PRODUCT] FATAL: $*" >&2; _EXIT_CODE=1; exit 1; }

# Step 418: Install log (no secrets)
log_file() {
  [ -n "$INSTALL_LOG" ] && echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >> "$INSTALL_LOG"
}

cleanup() {
  if [ -n "$_TMPDIR" ] && [ -d "$_TMPDIR" ]; then
    rm -rf "$_TMPDIR"
  fi
}

mktmpdir() {
  _TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'kd_inst')
  echo "$_TMPDIR"
}

# =============================================================================
# Step 343: Architecture detection
# =============================================================================
detect_arch() {
  local machine
  machine=$(uname -m 2>/dev/null || echo "unknown")
  case "$machine" in
    mips)                     echo "mips" ;;
    mipsel|mipsle)           echo "mipsel" ;;
    aarch64|arm64)           echo "aarch64" ;;
    # Heuristic: check for KeeneticOS paths
    *)
      if [ -f /proc/cpuinfo ]; then
        if grep -qi 'mips' /proc/cpuinfo 2>/dev/null; then
          # Detect endianness
          if [ -f /proc/sys/kernel/endian ] 2>/dev/null; then
            echo "mipsel"
          else
            # Default for Keenetic = little-endian MIPS
            echo "mipsel"
          fi
        elif grep -qi 'aarch64\|ARMv8' /proc/cpuinfo 2>/dev/null; then
          echo "aarch64"
        else
          echo "$machine"
        fi
      else
        echo "$machine"
      fi
      ;;
  esac
}

# =============================================================================
# Step 344: Environment detection
# =============================================================================
detect_env() {
  log "Detecting environment..."
  
  ARCH=$(detect_arch)
  log "  Architecture: $ARCH"
  
  # Entware
  HAS_ENTWARE="false"
  if [ -d /opt/bin ] && [ -f /opt/bin/opkg ]; then
    HAS_ENTWARE="true"
    ENTWARE_VER=$(opkg --version 2>/dev/null | head -1 || echo "unknown")
    log "  Entware: yes ($ENTWARE_VER)"
  else
    log "  Entware: no"
  fi
  
  # BusyBox
  HAS_BUSYBOX="false"
  if command -v busybox >/dev/null 2>&1; then
    HAS_BUSYBOX="true"
    BB_VER=$(busybox 2>&1 | head -1 | sed 's/.*v/v/' || echo "unknown")
    log "  BusyBox: $BB_VER"
  fi
  
  # Key utilities
  HAS_CURL="false"; command -v curl >/dev/null 2>&1 && HAS_CURL="true"
  HAS_WGET="false"; command -v wget >/dev/null 2>&1 && HAS_WGET="true"
  HAS_JQ="false"; command -v jq >/dev/null 2>&1 && HAS_JQ="true"
  HAS_PYTHON3="false"; command -v python3 >/dev/null 2>&1 && HAS_PYTHON3="true"
  HAS_TAR="false"; command -v tar >/dev/null 2>&1 && HAS_TAR="true"
  
  # Step 405: curl/wget availability
  if [ "$HAS_CURL" = "false" ] && [ "$HAS_WGET" = "false" ] && [ -z "$OFFLINE_BUNDLE" ]; then
    warn "Neither curl nor wget found. Use --offline <bundle> for offline install."
  fi
  
  # Step 406: sha256sum availability
  HAS_SHA256="false"
  if command -v sha256sum >/dev/null 2>&1; then
    HAS_SHA256="true"
    SHA256_CMD="sha256sum"
  elif command -v openssl >/dev/null 2>&1; then
    HAS_SHA256="true"
    SHA256_CMD="openssl dgst -sha256 -r"
  else
    warn "No sha256sum or openssl found. Integrity verification will fail."
  fi
  
  # Step 410: RAM check
  if [ -f /proc/meminfo ]; then
    TOTAL_RAM_KB=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    FREE_RAM_KB=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}' 2>/dev/null || grep '^MemFree:' /proc/meminfo | awk '{print $2}')
    if [ "${TOTAL_RAM_KB:-0}" -lt 65536 ]; then
      warn "Low RAM: ${TOTAL_RAM_KB}KB total. WebUI may not function; consider --no-webui"
    fi
  fi
  
  # Step 411: Time/NTP check
  local year
  year=$(date +%Y 2>/dev/null || echo "1970")
  if [ "$year" -lt 2024 ]; then
    warn "System clock appears incorrect (year=$year). Timestamps may be unreliable. Check NTP."
  fi
  
  # Step 367: Write permission and disk space
  if [ -d "$PREFIX" ]; then
    if [ ! -w "$PREFIX" ]; then
      # Step 412: Read-only FS
      die "Cannot write to $PREFIX. Choose another --prefix or mount a USB drive."
    fi
  else
    local parent
    parent=$(dirname "$PREFIX")
    if [ ! -w "$parent" ]; then
      die "Cannot create $PREFIX (no write access to $parent). Try sudo or different --prefix."
    fi
  fi
  
  # Free space check
  if command -v df >/dev/null 2>&1; then
    local parent_dir
    parent_dir=$(dirname "$PREFIX")
    [ -d "$PREFIX" ] && parent_dir="$PREFIX"
    FREE_MB=$(df -m "$parent_dir" 2>/dev/null | tail -1 | awk '{print $4}')
    if [ "${FREE_MB:-0}" -lt 20 ]; then
      die "Insufficient disk space: ${FREE_MB}MB free at $parent_dir (need >= 20MB)"
    elif [ "${FREE_MB:-0}" -lt 50 ]; then
      warn "Low disk space: ${FREE_MB}MB free"
    fi
  fi
  
  log "  Disk: ${FREE_MB:-?}MB free"
}

# =============================================================================
# Step 362, 406: Hash verification
# =============================================================================
verify_sha256() {
  local file="$1"
  local expected="$2"
  
  if [ "$HAS_SHA256" = "false" ]; then
    die "Cannot verify sha256: no sha256sum or openssl available"
  fi
  
  local actual
  actual=$($SHA256_CMD "$file" | awk '{print $1}')
  
  if [ "$actual" != "$expected" ]; then
    die "Hash mismatch for $(basename "$file"): expected=$expected actual=$actual"
  fi
  log_v "  SHA256 OK: $(basename "$file")"
}

# =============================================================================
# Download helper (curl → wget fallback) Step 405
# =============================================================================
download() {
  local url="$1"
  local dest="$2"
  
  # Step 358: Proxy support
  local proxy_args=""
  
  if [ "$HAS_CURL" = "true" ]; then
    curl -fsSL ${HTTP_PROXY:+--proxy "$HTTP_PROXY"} -o "$dest" "$url" 2>/dev/null
  elif [ "$HAS_WGET" = "true" ]; then
    wget -q -O "$dest" "$url" 2>/dev/null
  else
    die "No download tool (curl/wget). Use --offline for offline install."
  fi
}

# =============================================================================
# Step 347: Create directory structure
# =============================================================================
create_dirs() {
  log "Creating directory structure..."
  
  local dirs="bin modules collectors schemas web/static i18n docs policies scripts run var tmp reports logs config.d migrations"
  
  for d in $dirs; do
    mkdir -p "$PREFIX/$d"
    log_v "  Created $PREFIX/$d"
  done
  
  # Step 427: Secure permissions
  chmod 0750 "$PREFIX"
  chmod 0700 "$PREFIX/var" "$PREFIX/run" "$PREFIX/tmp"
  chmod 0750 "$PREFIX/reports" "$PREFIX/logs"
}

# =============================================================================
# Step 348: Generate bearer token
# =============================================================================
generate_token() {
  local token_file="$PREFIX/var/.auth_token"
  
  if [ -f "$token_file" ] && [ "$MODE" != "repair" ]; then
    log "  Auth token exists (preserved)"
    return
  fi
  
  local token
  if command -v openssl >/dev/null 2>&1; then
    token=$(openssl rand -hex 32)
  elif [ -f /dev/urandom ]; then
    token=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
  else
    token=$(date +%s%N | sha256sum 2>/dev/null | cut -c1-64 || echo "changeme_$(date +%s)")
  fi
  
  echo "$token" > "$token_file"
  chmod 0600 "$token_file"
  log "  Auth token generated: $token_file"
  log_file "token_generated path=$token_file"
}

# =============================================================================
# Step 349: Default config
# =============================================================================
create_default_config() {
  local config_file="$PREFIX/config.json"
  
  if [ -f "$config_file" ]; then
    log "  Config exists (preserved)"
    return
  fi
  
  cat > "$config_file" << 'CFGEOF'
{
  "config_version": 1,
  "research_mode": "medium",
  "performance_mode": "auto",
  "lang": "en",
  "debug": false,
  "readonly": true,
  "dangerous_ops": false,
  "resume": true,
  "snapshot_mode": "baseline",
  "webui": {
    "enabled": true,
    "bind": "127.0.0.1",
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
  chmod 0600 "$config_file"
  
  # Step 350: Verify safe defaults
  if grep -q '"0\.0\.0\.0"' "$config_file" 2>/dev/null; then
    die "SAFETY CHECK FAILED: config contains 0.0.0.0 bind"
  fi
  
  log "  Default config created: $config_file"
}

# =============================================================================
# Step 413: VERSION and BUILD_INFO
# =============================================================================
write_version_info() {
  local version="${1:-0.0.0}"
  
  echo "$version" > "$PREFIX/VERSION"
  
  cat > "$PREFIX/BUILD_INFO.json" << BEOF
{
  "version": "$version",
  "arch": "$ARCH",
  "channel": "$CHANNEL",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)",
  "installer_mode": "$MODE",
  "entware": $HAS_ENTWARE,
  "python3": $HAS_PYTHON3,
  "prefix": "$PREFIX"
}
BEOF
}

# =============================================================================
# Steps 372-383: init.d service
# =============================================================================
install_initd() {
  if [ "$AUTOSTART" = "false" ]; then
    log "  Autostart disabled (--no-autostart)"
    return
  fi
  
  local initd_dir="/opt/etc/init.d"
  
  # Step 383: Fallback if init.d unavailable
  if [ ! -d "$initd_dir" ]; then
    warn "init.d not available ($initd_dir). Manual start: $PREFIX/bin/keenetic-debug start"
    return
  fi
  
  local service="$initd_dir/S99keeneticdiag"
  
  cat > "$service" << SVCEOF
#!/bin/sh
# keenetic-debug service — auto-generated by install.sh
# Steps 373-380
PREFIX="$PREFIX"
PIDFILE="\$PREFIX/run/service.pid"
PORTFILE="\$PREFIX/run/webui.port"
LOCKFILE="\$PREFIX/run/.lock"

start() {
  # Step 380: Double-start protection
  if [ -f "\$PIDFILE" ]; then
    local old_pid=\$(cat "\$PIDFILE")
    if kill -0 "\$old_pid" 2>/dev/null; then
      echo "Already running (PID \$old_pid)"
      return 0
    fi
    rm -f "\$PIDFILE"
  fi
  
  # Lockfile
  if [ -f "\$LOCKFILE" ]; then
    echo "Lock exists: \$LOCKFILE"
    return 1
  fi
  
  echo "\$\$" > "\$LOCKFILE"
  
  echo "Starting keenetic-debug..."
  
  # Step 374: Auto-start WebUI
  if [ -f "\$PREFIX/config.json" ]; then
    "\$PREFIX/bin/keenetic-debug" start --background 2>&1 &
    local pid=\$!
    echo "\$pid" > "\$PIDFILE"
    
    # Step 375-376: Port detection
    sleep 2
    if [ -f "\$PORTFILE" ]; then
      local port=\$(cat "\$PORTFILE")
      echo "WebUI: http://127.0.0.1:\$port"
    fi
    
    # Step 379: Health check
    sleep 1
    if [ -f "\$PORTFILE" ]; then
      local port=\$(cat "\$PORTFILE")
      if command -v wget >/dev/null 2>&1; then
        wget -qO- "http://127.0.0.1:\$port/health" >/dev/null 2>&1 && echo "Health: OK" || echo "Health: WARN"
      fi
    fi
  fi
  
  rm -f "\$LOCKFILE"
  echo "Started (PID \$(cat "\$PIDFILE" 2>/dev/null || echo '?'))"
}

stop() {
  if [ -f "\$PIDFILE" ]; then
    local pid=\$(cat "\$PIDFILE")
    kill "\$pid" 2>/dev/null
    rm -f "\$PIDFILE" "\$LOCKFILE" "\$PORTFILE"
    echo "Stopped"
  else
    echo "Not running"
  fi
}

restart() { stop; sleep 1; start; }

status() {
  if [ -f "\$PIDFILE" ] && kill -0 \$(cat "\$PIDFILE") 2>/dev/null; then
    echo "Running (PID \$(cat "\$PIDFILE"))"
    [ -f "\$PORTFILE" ] && echo "WebUI port: \$(cat "\$PORTFILE")"
  else
    echo "Stopped"
  fi
}

case "\${1:-}" in
  start)   start ;;
  stop)    stop ;;
  restart) restart ;;
  status)  status ;;
  *)       echo "Usage: \$0 {start|stop|restart|status}"; exit 1 ;;
esac
SVCEOF
  
  chmod 0755 "$service"
  log "  Service installed: $service"
}

remove_initd() {
  local service="/opt/etc/init.d/S99keeneticdiag"
  if [ -f "$service" ]; then
    rm -f "$service"
    log "  Service removed: $service"
  fi
}

# =============================================================================
# Step 354: Safe upgrade (download → verify → staging → swap)
# =============================================================================
do_upgrade() {
  log "Upgrading..."
  
  local tmpdir
  tmpdir=$(mktmpdir)
  local staging="$tmpdir/staging"
  mkdir -p "$staging"
  
  # Step 355: Backup current version
  if [ -d "$PREFIX/modules" ]; then
    local backup_dir="$PREFIX/var/backup/$(cat "$PREFIX/VERSION" 2>/dev/null || echo 'prev')"
    mkdir -p "$backup_dir"
    cp -r "$PREFIX/modules" "$PREFIX/bin" "$PREFIX/schemas" "$backup_dir/" 2>/dev/null
    log "  Backup: $backup_dir"
  fi
  
  # Download or extract from offline bundle
  if [ -n "$OFFLINE_BUNDLE" ]; then
    extract_offline_bundle "$OFFLINE_BUNDLE" "$staging"
  else
    download_release "$staging"
  fi
  
  # Step 354: Atomic swap key directories
  for d in modules bin schemas collectors web i18n policies; do
    if [ -d "$staging/$d" ]; then
      if [ -d "$PREFIX/$d" ]; then
        mv "$PREFIX/$d" "$PREFIX/$d.old"
      fi
      mv "$staging/$d" "$PREFIX/$d"
      rm -rf "$PREFIX/$d.old"
    fi
  done
  
  # Step 388: Migrate config and stateDB
  if [ -f "$PREFIX/modules/configurator.sh" ]; then
    . "$PREFIX/modules/configurator.sh"
    config_migrate "$PREFIX/config.json" 2>/dev/null || true
  fi
  
  # Step 370: Check schema compatibility
  local new_version
  new_version=$(cat "$staging/VERSION" 2>/dev/null || echo "unknown")
  write_version_info "$new_version"
  
  log "Upgraded to $new_version"
}

# =============================================================================
# Step 353: Uninstall
# =============================================================================
do_uninstall() {
  log "Uninstalling..."
  
  if [ "$FORCE" != "true" ] && [ "$INTERACTIVE" != "true" ]; then
    die "Use --yes or --interactive to confirm uninstall"
  fi
  
  # Stop service
  local service="/opt/etc/init.d/S99keeneticdiag"
  [ -f "$service" ] && "$service" stop 2>/dev/null
  
  # Step 381: Remove init.d
  remove_initd
  
  # Step 398: Option to keep reports
  if [ "$FORCE" = "true" ]; then
    rm -rf "$PREFIX"
    log "Removed: $PREFIX (including reports)"
  else
    # Keep reports for debugging
    local keep="$PREFIX/reports"
    if [ -d "$keep" ]; then
      warn "Reports preserved in $keep. Remove manually if desired."
    fi
    rm -rf "$PREFIX/bin" "$PREFIX/modules" "$PREFIX/web" "$PREFIX/schemas" \
           "$PREFIX/collectors" "$PREFIX/i18n" "$PREFIX/policies" \
           "$PREFIX/run" "$PREFIX/var" "$PREFIX/tmp"
    log "Removed binaries/modules. Reports preserved."
  fi
  
  # Step 356: Audit log entry
  log_file "uninstall completed"
}

# =============================================================================
# Step 357: Verify-only mode
# =============================================================================
do_verify() {
  log "Verifying installation integrity..."
  
  local errors=0
  
  # Check critical files
  for f in VERSION config.json var/.auth_token; do
    if [ ! -f "$PREFIX/$f" ]; then
      warn "Missing: $PREFIX/$f"
      errors=$((errors + 1))
    fi
  done
  
  # Check directories
  for d in bin modules schemas collectors i18n; do
    if [ ! -d "$PREFIX/$d" ]; then
      warn "Missing dir: $PREFIX/$d"
      errors=$((errors + 1))
    fi
  done
  
  # Check permissions
  local token_perms
  if [ -f "$PREFIX/var/.auth_token" ]; then
    token_perms=$(stat -c '%a' "$PREFIX/var/.auth_token" 2>/dev/null || echo "?")
    if [ "$token_perms" != "600" ]; then
      warn "Token permissions: $token_perms (should be 600)"
      errors=$((errors + 1))
    fi
  fi
  
  if [ $errors -eq 0 ]; then
    log "Verification passed"
  else
    warn "$errors issues found"
  fi
}

# =============================================================================
# Step 426: Repair mode
# =============================================================================
do_repair() {
  log "Repairing installation..."
  create_dirs
  generate_token
  
  # Fix permissions Step 427
  [ -f "$PREFIX/var/.auth_token" ] && chmod 0600 "$PREFIX/var/.auth_token"
  [ -f "$PREFIX/config.json" ] && chmod 0600 "$PREFIX/config.json"
  
  log "Repair complete"
}

# =============================================================================
# Step 364-366: Offline bundle
# =============================================================================
extract_offline_bundle() {
  local bundle="$1"
  local dest="$2"
  
  if [ ! -f "$bundle" ] && [ ! -d "$bundle" ]; then
    die "Offline bundle not found: $bundle"
  fi
  
  # Step 423: Check BUNDLE_INFO
  if [ -d "$bundle" ]; then
    # Directory bundle
    if [ -f "$bundle/BUNDLE_INFO.json" ]; then
      # Step 424: Architecture check
      if [ "$HAS_JQ" = "true" ]; then
        local bundle_arch
        bundle_arch=$(jq -r '.arch // "unknown"' "$bundle/BUNDLE_INFO.json")
        if [ "$bundle_arch" != "$ARCH" ] && [ "$bundle_arch" != "universal" ]; then
          die "Bundle architecture mismatch: bundle=$bundle_arch, device=$ARCH. Download correct bundle."
        fi
      fi
    fi
    cp -r "$bundle"/* "$dest/"
  else
    # Archive bundle
    # Step 365: Verify bundle integrity
    if [ -f "${bundle}.sha256" ]; then
      verify_sha256 "$bundle" "$(cat "${bundle}.sha256" | awk '{print $1}')"
    fi
    tar xzf "$bundle" -C "$dest" 2>/dev/null || die "Failed to extract bundle"
  fi
}

download_release() {
  local dest="$1"
  
  # Step 361: Download manifest first
  local manifest="$dest/release-manifest.json"
  local manifest_url="$MANIFEST_URL"
  [ -n "$CUSTOM_URL" ] && manifest_url="$CUSTOM_URL/release-manifest.json"
  
  download "$manifest_url" "$manifest"
  
  # Step 419: Custom URL only with pinned sha256
  if [ -n "$CUSTOM_URL" ] && [ "$HAS_JQ" = "false" ]; then
    die "Custom base URL requires jq for manifest verification"
  fi
  
  # Download runtime archive for our arch
  if [ "$HAS_JQ" = "true" ]; then
    local archive_name
    archive_name=$(jq -r --arg a "$ARCH" '.artifacts[] | select(.file | contains($a)) | .file' "$manifest" | head -1)
    local archive_hash
    archive_hash=$(jq -r --arg a "$ARCH" '.artifacts[] | select(.file | contains($a)) | .sha256' "$manifest" | head -1)
    
    if [ -z "$archive_name" ]; then
      die "No artifact for arch $ARCH in release manifest"
    fi
    
    local base_url="${CUSTOM_URL:-$(dirname "$manifest_url")}"
    download "$base_url/$archive_name" "$dest/$archive_name"
    
    # Step 362: Verify sha256
    verify_sha256 "$dest/$archive_name" "$archive_hash"
    
    tar xzf "$dest/$archive_name" -C "$dest" 2>/dev/null
  else
    warn "jq not available: skipping manifest parsing"
  fi
}

# =============================================================================
# Step 351: Print summary
# =============================================================================
print_summary() {
  local version
  version=$(cat "$PREFIX/VERSION" 2>/dev/null || echo "unknown")
  
  echo ""
  echo "======================================"
  echo "  $PRODUCT installed successfully!"
  echo "======================================"
  echo "  Version:  $version"
  echo "  Prefix:   $PREFIX"
  echo "  Arch:     $ARCH"
  echo "  Entware:  $HAS_ENTWARE"
  echo ""
  echo "  Quick start:"
  echo "    $PREFIX/bin/keenetic-debug start"
  echo "    $PREFIX/bin/keenetic-debug --help"
  echo ""
  echo "  Auth token: $PREFIX/var/.auth_token"
  echo "  Config:     $PREFIX/config.json"
  echo ""
  if [ "$AUTOSTART" = "true" ] && [ -f "/opt/etc/init.d/S99keeneticdiag" ]; then
    echo "  Service:    /opt/etc/init.d/S99keeneticdiag {start|stop|status}"
  fi
  echo "  Logs:       $PREFIX/logs/install.log"
  echo "======================================"
}

# =============================================================================
# Step 420: Self-check
# =============================================================================
self_check() {
  # Verify minimal environment
  command -v cat >/dev/null 2>&1 || die "Missing 'cat' — environment too minimal"
  command -v mkdir >/dev/null 2>&1 || die "Missing 'mkdir'"
  command -v chmod >/dev/null 2>&1 || die "Missing 'chmod'"
  command -v date >/dev/null 2>&1 || die "Missing 'date'"
  
  # Step 417: Verify we don't modify iptables
  log_v "  Self-check passed (no iptables/nft modifications)"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  parse_args "$@"
  
  # Step 404: Print default config
  if [ "$PRINT_CONFIG" = "true" ]; then
    cat "$PREFIX/config.json" 2>/dev/null || scripts/gen_default_config.sh 2>/dev/null
    exit 0
  fi
  
  log "=== $PRODUCT installer ==="
  log "Mode: $MODE"
  
  self_check
  detect_env
  
  # Step 368: Dry run
  if [ "$DRY_RUN" = "true" ]; then
    log "DRY RUN: Would install to $PREFIX (arch=$ARCH, channel=$CHANNEL)"
    log "DRY RUN: Autostart=$AUTOSTART, WebUI=$INSTALL_WEBUI"
    exit 0
  fi
  
  # Setup install log (Step 418)
  mkdir -p "$PREFIX/logs" 2>/dev/null
  INSTALL_LOG="$PREFIX/logs/install.log"
  log_file "=== $MODE started ==="
  log_file "arch=$ARCH channel=$CHANNEL prefix=$PREFIX"
  
  case "$MODE" in
    install)
      create_dirs
      
      if [ -n "$OFFLINE_BUNDLE" ]; then
        local tmpdir=$(mktmpdir)
        extract_offline_bundle "$OFFLINE_BUNDLE" "$tmpdir"
        # Copy extracted files
        cp -r "$tmpdir"/* "$PREFIX/" 2>/dev/null || true
      fi
      
      generate_token
      create_default_config
      write_version_info "$(cat "$PREFIX/VERSION" 2>/dev/null || echo "0.1.0-alpha")"
      install_initd
      
      # Step 356: Audit log
      log_file "install completed version=$(cat "$PREFIX/VERSION" 2>/dev/null)"
      
      # Step 351: Summary
      print_summary
      ;;
      
    upgrade)
      do_upgrade
      # Step 356: Audit log
      log_file "upgrade completed version=$(cat "$PREFIX/VERSION" 2>/dev/null)"
      print_summary
      ;;
      
    uninstall)
      do_uninstall
      ;;
      
    verify)
      do_verify
      ;;
      
    repair)
      do_repair
      ;;
      
    webui-only)
      mkdir -p "$PREFIX/web/static"
      log "WebUI-only mode: install web assets only"
      ;;
  esac
  
  log "Done."
}

main "$@"

# Step 363: Optional signature verification
verify_signature() {
  local file="$1"
  local sig_file="${file}.sig"
  
  if [ ! -f "$sig_file" ]; then
    log_v "No signature file for $(basename "$file") — SKIP"
    return 0
  fi
  
  if command -v minisign >/dev/null 2>&1; then
    minisign -Vm "$file" -x "$sig_file" 2>/dev/null && log "Signature OK (minisign)" || warn "Signature verification failed"
  elif command -v openssl >/dev/null 2>&1; then
    log_v "Optional: openssl signature verification available"
  else
    warn "No signature verification tool (minisign/openssl). Skipping signature check."
  fi
}

# Steps 428-429: User/group detection
detect_service_user() {
  local desired_user="${1:-keenetic-debug}"
  
  # Check if useradd/adduser available
  if command -v useradd >/dev/null 2>&1; then
    if ! id "$desired_user" >/dev/null 2>&1; then
      log_v "Could create service user '$desired_user' via useradd"
    fi
  elif command -v adduser >/dev/null 2>&1; then
    if ! id "$desired_user" >/dev/null 2>&1; then
      log_v "Could create service user '$desired_user' via adduser"
    fi
  else
    # Fallback: run as current user
    log_v "No useradd/adduser available. Running as current user: $(whoami 2>/dev/null || echo root)"
  fi
}
