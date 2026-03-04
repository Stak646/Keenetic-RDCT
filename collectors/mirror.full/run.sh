#!/bin/sh
# Collector: mirror.full
set -eu
BASE_DIR="${TOOL_BASE_DIR:-/opt/keenetic-debug}"
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
RESULT="$WORKDIR/result.json"
mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0; cmds_fail=0; skipped=""
. "$BASE_DIR/modules/lib/json_writer.sh" 2>/dev/null || true
. "$BASE_DIR/modules/lib/hash.sh" 2>/dev/null || true
. "$BASE_DIR/modules/lib/safe_read.sh" 2>/dev/null || true

collect() { local cmd="$1" out="$2" fb="${3:-}"; local t=$(echo "$cmd"|awk '{print $1}'); if command -v "$t" >/dev/null 2>&1; then eval "$cmd" > "$ARTIFACTS/$out" 2>/dev/null && cmds_run=$((cmds_run+1)) || cmds_fail=$((cmds_fail+1)); elif [ -n "$fb" ]; then local ft=$(echo "$fb"|awk '{print $1}'); if command -v "$ft" >/dev/null 2>&1; then eval "$fb" > "$ARTIFACTS/$out" 2>/dev/null && cmds_run=$((cmds_run+1)); else cmds_fail=$((cmds_fail+1)); fi; else cmds_fail=$((cmds_fail+1)); fi; }
read_file() { local src="$1" out="$2"; [ -r "$src" ] && head -c 524288 "$src" > "$ARTIFACTS/$out" 2>/dev/null && cmds_run=$((cmds_run+1)) || cmds_fail=$((cmds_fail+1)); }

### DATA ###
. "$BASE_DIR/modules/lib/safe_read.sh" 2>/dev/null || true
MIRROR_MAX_FILES=${MIRROR_MAX_FILES:-10000}
MIRROR_MAX_DEPTH=${MIRROR_MAX_DEPTH:-10}
WORKDIR_ABS=$(cd "$WORKDIR" 2>/dev/null && pwd)
find /opt -maxdepth $MIRROR_MAX_DEPTH -type f \
  ! -path "*/keenetic-debug/tmp/*" ! -path "*/keenetic-debug/reports/*" \
  ! -path "*/keenetic-debug/run/*" ! -name "*.tar.gz" ! -name "*.zip" \
  2>/dev/null | head -$MIRROR_MAX_FILES | while read -r f; do
  case "$f" in "$WORKDIR_ABS"*) continue ;; esac
  fsize=$(wc -c < "$f" 2>/dev/null || echo 0)
  [ "$fsize" -gt 10485760 ] && continue
  rel=$(echo "$f" | sed "s|^/opt/||" | tr "/" "_")
  cp "$f" "$ARTIFACTS/$rel" 2>/dev/null && cmds_run=$((cmds_run+1))
done

### RESULT ###
out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
fp=""; command -v sha256sum >/dev/null 2>&1 && fp=$(find "$ARTIFACTS" -type f -exec sha256sum {} + 2>/dev/null | sha256sum | awk '{print $1}')
cat > "$RESULT" << RESEOF
{"schema_id":"result","schema_version":"1","collector_id":"mirror.full","status":"$status","started_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)","finished_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)","duration_ms":0,"metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run,"commands_skipped":0,"commands_failed":$cmds_fail},"data":{},"artifacts":[${arts%,}],"errors":[],"fingerprint":"$fp"}
RESEOF
exit 0
