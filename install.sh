#!/bin/sh
set -eu

# RDCT installer (USB-only) — designed to be runnable as a GitHub one-liner:
#   curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | sh
#
# Principles:
# - Never write to internal storage (everything goes to USB)
# - Minimal dependencies: sh + (curl or wget) + tar + (sha256sum or openssl)
# - Optional Entware opkg deps install (default enabled; can be disabled)
#
# ---- user-tunable env ----
# Where to install (MUST be on USB)
RDCT_BASE="${RDCT_BASE:-}"

# Which GitHub repo to download from
# If you run this script from a cloned repo, it can infer owner/repo from git remote.
RDCT_GH_OWNER="${RDCT_GH_OWNER:-}"
RDCT_GH_REPO="${RDCT_GH_REPO:-}"
RDCT_GH_REF="${RDCT_GH_REF:-main}"   # main | vX.Y.Z | commit

# Prefer release asset download (requires GitHub API). If false, download source tarball.
RDCT_USE_RELEASES="${RDCT_USE_RELEASES:-1}"   # 1/0

# Auto-install deps via opkg (Entware). Default ON; disable with RDCT_NO_DEPS=1
RDCT_NO_DEPS="${RDCT_NO_DEPS:-0}"

# ---- helpers ----
log() { printf '%s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 2; }

have() { command -v "$1" >/dev/null 2>&1; }

is_tty() { [ -t 0 ] 2>/dev/null; }

prompt_yn() {
  # usage: prompt_yn "Question" "Y"
  q="$1"; dflt="$2"
  if ! is_tty; then
    # non-interactive: default
    [ "$dflt" = "Y" ] && return 0 || return 1
  fi
  while :; do
    printf "%s [%s/%s]: " "$q" "${dflt}" "$( [ "$dflt" = "Y" ] && echo N || echo Y )" >&2
    read ans || ans=""
    ans="$(echo "$ans" | tr '[:upper:]' '[:lower:]')"
    if [ -z "$ans" ]; then ans="$(echo "$dflt" | tr '[:upper:]' '[:lower:]')"; fi
    case "$ans" in
      y|yes) return 0;;
      n|no) return 1;;
    esac
  done
}

# Detect external mounts from /proc/mounts (best-effort for Keenetic/Entware)
detect_usb_mounts() {
  # output: "<mountpoint> <device> <fstype> <opts>"
  awk '
    $3 !~ /^(proc|sysfs|tmpfs|devtmpfs|overlay|squashfs|ramfs|cgroup|cgroup2)$/ {
      dev=$1; mp=$2; fs=$3; opts=$4;
      if (dev ~ /^\/dev\/(sd[a-z][0-9]*|mmcblk[0-9]+p?[0-9]*|nvme[0-9]+n[0-9]+p?[0-9]*|usb[^ ]*)$/) {
        print mp " " dev " " fs " " opts;
      } else if (dev ~ /^UUID=/ && (mp ~ /\/tmp\/mnt\// || mp ~ /\/mnt\// || mp ~ /\/media\//)) {
        print mp " " dev " " fs " " opts;
      }
    }' /proc/mounts 2>/dev/null | sort -r
}

choose_usb_mount() {
  mounts="$(detect_usb_mounts || true)"
  [ -n "$mounts" ] || die "USB mount not detected. Plug USB drive and ensure it is mounted."

  # If only one mount — use it
  count="$(echo "$mounts" | grep -c '^[^ ]')"
  if [ "$count" -eq 1 ]; then
    echo "$mounts" | head -n1
    return 0
  fi

  # Multiple mounts: if interactive, ask; otherwise pick first.
  if ! is_tty; then
    echo "$mounts" | head -n1
    return 0
  fi

  log "Detected multiple external mounts:" 
  i=0
  echo "$mounts" | while IFS= read -r line; do
    i=$((i+1))
    mp="$(echo "$line" | awk '{print $1}')"
    dev="$(echo "$line" | awk '{print $2}')"
    fs="$(echo "$line" | awk '{print $3}')"
    log "  [$i] $mp ($dev, $fs)"
  done

  while :; do
    printf "Select USB mount [1-%s]: " "$count" >&2
    read sel || sel="1"
    case "$sel" in
      ''|*[!0-9]*) continue;;
    esac
    if [ "$sel" -ge 1 ] && [ "$sel" -le "$count" ]; then
      echo "$mounts" | sed -n "${sel}p"
      return 0
    fi
  done
}

ensure_on_usb() {
  base="$1"
  mp="$2"
  case "$base" in
    "$mp"/*|"$mp") return 0;;
    *) die "USB-only enforced: RDCT_BASE must be under $mp (got: $base)";;
  esac
}

fetch() {
  url="$1"; out="$2"
  if have curl; then
    curl -fsSL "$url" -o "$out"
    return $?
  fi
  if have wget; then
    wget -qO "$out" "$url"
    return $?
  fi
  die "Need curl or wget to download: $url"
}

sha256_check() {
  file="$1"; expected="$2"
  if have sha256sum; then
    got="$(sha256sum "$file" | awk '{print $1}')"
  elif have openssl; then
    got="$(openssl dgst -sha256 "$file" | awk '{print $NF}')"
  else
    log "WARN: sha256sum/openssl not found; skipping integrity check"
    return 0
  fi
  [ "$got" = "$expected" ] || die "SHA256 mismatch for $(basename "$file"): expected=$expected got=$got"
}

# ---- main ----

# If owner/repo not provided, try to infer from git remote (when running from a cloned repo)
if [ -z "$RDCT_GH_OWNER" ] || [ -z "$RDCT_GH_REPO" ]; then
  if have git; then
    ORIGIN_URL="$(git config --get remote.origin.url 2>/dev/null || true)"
    if [ -n "$ORIGIN_URL" ]; then
      case "$ORIGIN_URL" in
        https://github.com/*/*)
          TMP="${ORIGIN_URL#https://github.com/}"
          TMP="${TMP%.git}"
          RDCT_GH_OWNER="${TMP%%/*}"
          RDCT_GH_REPO="${TMP#*/}"
          ;;
        git@github.com:*/*)
          TMP="${ORIGIN_URL#git@github.com:}"
          TMP="${TMP%.git}"
          RDCT_GH_OWNER="${TMP%%/*}"
          RDCT_GH_REPO="${TMP#*/}"
          ;;
      esac
    fi
  fi
fi

if [ -z "$RDCT_GH_OWNER" ] || [ -z "$RDCT_GH_REPO" ]; then
  die "RDCT_GH_OWNER/RDCT_GH_REPO are not set. Example:\n  curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | RDCT_GH_OWNER=<OWNER> RDCT_GH_REPO=<REPO> sh"
fi

sel_line="$(choose_usb_mount)"
USB_MP="$(echo "$sel_line" | awk '{print $1}')"
USB_DEV="$(echo "$sel_line" | awk '{print $2}')"
USB_FS="$(echo "$sel_line" | awk '{print $3}')"
USB_OPTS="$(echo "$sel_line" | awk '{print $4}')"

if [ -z "$RDCT_BASE" ]; then
  RDCT_BASE="$USB_MP/rdct"
fi

ensure_on_usb "$RDCT_BASE" "$USB_MP"

# Directory layout
BASE="$RDCT_BASE"
INSTALL_DIR="$BASE/install"
DEPS_DIR="$BASE/deps"
CACHE_DIR="$BASE/cache"
RUN_DIR="$BASE/run"
REPORTS_DIR="$BASE/reports"
LOGS_DIR="$BASE/logs"
CONFIG_DIR="$BASE/config"
APPS_DIR="$BASE/apps"

mkdir -p "$INSTALL_DIR" "$DEPS_DIR" "$CACHE_DIR" "$RUN_DIR" "$REPORTS_DIR" "$LOGS_DIR" "$CONFIG_DIR" "$APPS_DIR"

log "RDCT USB mount: $USB_MP ($USB_DEV, fs=$USB_FS, opts=$USB_OPTS)"
log "RDCT base path: $BASE"

# Health checks (RW + free space)
if echo "$USB_OPTS" | grep -q '\bro\b'; then
  die "USB filesystem is mounted read-only (ro). Remount RW or use another USB drive."
fi

# Download package
TMP="$RUN_DIR/install_tmp"
rm -rf "$TMP"; mkdir -p "$TMP"

TARBALL="$TMP/rdct.tar.gz"
SHAFILE="$TMP/rdct.sha256"

# Decide download method
if [ "$RDCT_USE_RELEASES" = "1" ] && [ "$RDCT_GH_OWNER" != "<OWNER>" ] && [ "$RDCT_GH_REPO" != "<REPO>" ]; then
  # Try GitHub Releases latest via API. We avoid jq; use simple parsing.
  API_URL="https://api.github.com/repos/$RDCT_GH_OWNER/$RDCT_GH_REPO/releases/latest"
  JSON="$TMP/release.json"
  log "Fetching latest release metadata: $API_URL"
  if fetch "$API_URL" "$JSON"; then
    # Expect an asset called rdct-release.tar.gz and rdct-release.sha256
    ASSET_URL="$(grep -E '"browser_download_url"' "$JSON" | grep -E 'rdct-release\\.tar\\.gz"' | head -n1 | sed -E 's/.*"(https:[^"]+)".*/\1/')"
    SHA_URL="$(grep -E '"browser_download_url"' "$JSON" | grep -E 'rdct-release\\.sha256"' | head -n1 | sed -E 's/.*"(https:[^"]+)".*/\1/')"
    if [ -n "$ASSET_URL" ] && [ -n "$SHA_URL" ]; then
      log "Downloading release asset: $ASSET_URL"
      fetch "$ASSET_URL" "$TARBALL"
      log "Downloading sha256: $SHA_URL"
      fetch "$SHA_URL" "$SHAFILE" || true
    else
      log "WARN: release assets not found in latest release; falling back to source tarball"
      RDCT_USE_RELEASES=0
    fi
  else
    log "WARN: GitHub API not доступен; falling back to source tarball"
    RDCT_USE_RELEASES=0
  fi
fi

if [ "$RDCT_USE_RELEASES" != "1" ]; then
  [ "$RDCT_GH_OWNER" != "<OWNER>" ] || die "Set RDCT_GH_OWNER/RDCT_GH_REPO or edit install.sh placeholders."
  [ "$RDCT_GH_REPO" != "<REPO>" ] || die "Set RDCT_GH_OWNER/RDCT_GH_REPO or edit install.sh placeholders."
  SRC_URL="https://codeload.github.com/$RDCT_GH_OWNER/$RDCT_GH_REPO/tar.gz/$RDCT_GH_REF"
  log "Downloading source tarball: $SRC_URL"
  fetch "$SRC_URL" "$TARBALL"
fi

# Verify sha256 if we have it
if [ -s "$SHAFILE" ]; then
  # sha file can be "<sha>  <name>" or just sha
  EXPECTED="$(awk '{print $1}' "$SHAFILE" | head -n1)"
  if [ -n "$EXPECTED" ]; then
    log "Verifying sha256..."
    sha256_check "$TARBALL" "$EXPECTED"
    log "OK: sha256 verified"
  fi
else
  log "NOTE: sha256 file not available; skipping integrity verification"
fi

# Extract to INSTALL_DIR (replace old)
rm -rf "$INSTALL_DIR"; mkdir -p "$INSTALL_DIR"

log "Extracting into: $INSTALL_DIR"
# Try tar --strip-components=1 (GNU tar). If unsupported, extract to temp and move.
if tar --help 2>/dev/null | grep -q 'strip-components'; then
  tar -xzf "$TARBALL" -C "$INSTALL_DIR" --strip-components=1
else
  EX="$TMP/extract"
  rm -rf "$EX"; mkdir -p "$EX"
  tar -xzf "$TARBALL" -C "$EX"
  TOP="$(ls -1 "$EX" | head -n1)"
  [ -n "$TOP" ] || die "Extraction failed"
  # If repo root contains a single top folder, move its content
  if [ -d "$EX/$TOP" ]; then
    (cd "$EX/$TOP" && tar -cf - .) | (cd "$INSTALL_DIR" && tar -xf -)
  else
    (cd "$EX" && tar -cf - .) | (cd "$INSTALL_DIR" && tar -xf -)
  fi
fi

# Create wrapper in BASE (so user can run without cd)
cat > "$BASE/rdct.sh" <<'WRAP'
#!/bin/sh
set -eu
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
PY="${PYTHON:-python3}"
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="$BASE_DIR/install${PYTHONPATH:+:$PYTHONPATH}"
exec "$PY" -m rdct.cli --base "$BASE_DIR" "$@"
WRAP
chmod +x "$BASE/rdct.sh"

# Dependencies (optional)
if [ "$RDCT_NO_DEPS" = "1" ]; then
  log "Skipping dependency installation (RDCT_NO_DEPS=1)"
else
  if ! have python3; then
    # Attempt opkg install if available
    OPKG=""
    [ -x /opt/bin/opkg ] && OPKG=/opt/bin/opkg
    [ -x /opt/sbin/opkg ] && OPKG=/opt/sbin/opkg

    if [ -n "$OPKG" ]; then
      # Safety: ensure /opt is on USB (best-effort)
      OPT_MP="$(awk '$2=="/opt"{print $1" "$2" "$3" "$4}' /proc/mounts 2>/dev/null | head -n1 | awk '{print $1}')"
      if [ -z "$OPT_MP" ]; then
        log "WARN: /opt is not a mountpoint; cannot verify USB-only for Entware."
      fi

      if prompt_yn "python3 not found. Install python3 via opkg (Entware)?" "Y"; then
        log "Running: opkg update (network required)"
        "$OPKG" update || true
        log "Running: opkg install python3"
        "$OPKG" install python3 || die "opkg install python3 failed"
      else
        die "python3 is required. Install python3 (Entware) or set RDCT_NO_DEPS=1 and provide python3 yourself."
      fi
    else
      die "python3 not found and opkg is unavailable. Install python3 first (Entware), then re-run installer."
    fi
  fi
fi

# Initialize config
log "Initializing config..."
"$BASE/rdct.sh" init || true

# Pick a port (best-effort)
choose_port() {
  # try 8080..8090; fallback 0
  if have ss; then
    used="$(ss -lnt 2>/dev/null | awk 'NR>1{print $4}' | sed -E 's/.*:([0-9]+)$/\1/' | sort -n | uniq)"
  elif have netstat; then
    used="$(netstat -lnt 2>/dev/null | awk 'NR>2{print $4}' | sed -E 's/.*:([0-9]+)$/\1/' | sort -n | uniq)"
  else
    used=""
  fi
  p=8080
  while [ "$p" -le 8090 ]; do
    if echo "$used" | grep -qx "$p"; then
      p=$((p+1))
    else
      echo "$p"; return 0
    fi
  done
  echo 0
}

PORT="$(choose_port)"

# Update config server.port if python available
if have python3; then
  python3 - <<PY
import json
from pathlib import Path
base = Path("$BASE")
cp = base / "config" / "rdct.json"
try:
  cfg = json.loads(cp.read_text(encoding='utf-8'))
except Exception:
  cfg = {}
server = cfg.setdefault('server', {})
server.setdefault('bind', '0.0.0.0')
server['port'] = int("$PORT")
server.setdefault('enabled', True)
cp.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding='utf-8')
print(server.get('token',''))
PY
fi

TOKEN="$( (python3 -c 'import json;import pathlib; p=pathlib.Path("'$BASE'/config/rdct.json"); print(json.loads(p.read_text()).get("server",{}).get("token",""))' 2>/dev/null) || true )"

log "\nInstalled RDCT successfully."
log "Base: $BASE"
log "Run:  $BASE/rdct.sh preflight"
log "Run:  $BASE/rdct.sh run --mode light"
log "Web:  $BASE/rdct.sh serve --bind 0.0.0.0 --port $PORT"
if [ -n "$TOKEN" ]; then
  log "Token: $TOKEN"
fi
if [ "$PORT" != "0" ]; then
  log "URL:   http://<router-ip>:$PORT/"
else
  log "NOTE: port=0 (auto). Start server to see chosen port in logs." 
fi

exit 0
