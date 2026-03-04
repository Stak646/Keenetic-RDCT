#!/bin/sh
# Collector: config.keenetic_rci — Keenetic RCI Config
set -eu
BASE_DIR="${TOOL_BASE_DIR:-/opt/keenetic-debug}"
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
RESULT="$WORKDIR/result.json"
MODE="${RESEARCH_MODE:-medium}"

. "$BASE_DIR/modules/lib/json_writer.sh" 2>/dev/null || true
. "$BASE_DIR/modules/lib/hash.sh" 2>/dev/null || true
. "$BASE_DIR/modules/lib/safe_read.sh" 2>/dev/null || true

mkdir -p "$ARTIFACTS"

status="OK"
cmds_run=0
cmds_fail=0
warnings=""
skipped=""

collect() {
  local cmd="$1" out="$2" fb="${3:-}"
  local tool=$(echo "$cmd" | awk '{print $1}')
  if command -v "$tool" >/dev/null 2>&1; then
    eval "$cmd" > "$ARTIFACTS/$out" 2>/dev/null && cmds_run=$((cmds_run+1)) || cmds_fail=$((cmds_fail+1))
  elif [ -n "$fb" ]; then
    local fbtool=$(echo "$fb" | awk '{print $1}')
    if command -v "$fbtool" >/dev/null 2>&1; then
      eval "$fb" > "$ARTIFACTS/$out" 2>/dev/null && cmds_run=$((cmds_run+1)) || cmds_fail=$((cmds_fail+1))
    else cmds_fail=$((cmds_fail+1)); fi
  else cmds_fail=$((cmds_fail+1)); fi
}

read_file() {
  local src="$1" out="$2" max_kb="${3:-512}"
  if [ -r "$src" ]; then
    head -c $((max_kb*1024)) "$src" > "$ARTIFACTS/$out" 2>/dev/null && cmds_run=$((cmds_run+1))
  else cmds_fail=$((cmds_fail+1)); skipped="${skipped}$src,"; fi
}

# Sandbox support
if [ "${TOOL_SANDBOX:-0}" = "1" ]; then
  FIX="${SANDBOX_FIXTURES:-$BASE_DIR/tests/fixtures/sandbox}"
fi

### DATA COLLECTION ###
if command -v ndmc >/dev/null 2>&1; then
  for q in "show version" "show interface" "show ip route" "show ip hotspot" "show system"; do
    safe_name=$(echo "$q" | tr " " "_")
    ndmc -c "$q" > "$ARTIFACTS/rci_${safe_name}.json" 2>/dev/null && cmds_run=$((cmds_run+1)) || cmds_fail=$((cmds_fail+1))
  done
elif command -v curl >/dev/null 2>&1; then
  curl -fsS --max-time 5 "http://127.0.0.1:79/rci/show/version" > "$ARTIFACTS/rci_version.json" 2>/dev/null && cmds_run=$((cmds_run+1))
else
  status="SKIP"; cmds_fail=$((cmds_fail+1))
fi

### RESULT ###
out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""
for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done

fp=""
if command -v sha256sum >/dev/null 2>&1; then
  fp=$(find "$ARTIFACTS" -type f -exec sha256sum {} + 2>/dev/null | sha256sum | awk '{print $1}')
fi

cat > "$RESULT" << RESEOF
{
  "schema_id":"result","schema_version":"1",
  "collector_id":"config.keenetic_rci","status":"$status",
  "started_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)",
  "finished_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)",
  "duration_ms":0,
  "metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run,"commands_skipped":0,"commands_failed":$cmds_fail},
  "data":{},
  "artifacts":[${arts%,}],
  "errors":[],"warnings":[],"skipped_items":[$(echo "$skipped" | sed 's/,$//' | sed 's/\([^,]*\)/"\1"/g')],
  "fingerprint":"$fp"
}
RESEOF
exit 0
