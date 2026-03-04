#!/bin/sh
# Collector: COLLECTOR_ID
# Category: CATEGORY
# Description: COLLECTOR_NAME
set -eu

# --- Framework libraries ---
BASE_DIR="${TOOL_BASE_DIR:-/opt/keenetic-debug}"
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
RESULT="$WORKDIR/result.json"

# Source libraries
. "$BASE_DIR/modules/lib/json_writer.sh" 2>/dev/null || true
. "$BASE_DIR/modules/lib/hash.sh" 2>/dev/null || true
. "$BASE_DIR/modules/lib/safe_read.sh" 2>/dev/null || true
. "$BASE_DIR/modules/lib/fingerprint.sh" 2>/dev/null || true

mkdir -p "$ARTIFACTS"

# --- Mode check ---
MODE="${RESEARCH_MODE:-medium}"
PERF="${PERF_MODE:-auto}"

# --- Sandbox support (Step 639) ---
if [ "${TOOL_SANDBOX:-0}" = "1" ]; then
  FIXTURES="${SANDBOX_FIXTURES:-$BASE_DIR/tests/fixtures/sandbox}"
  # Read from fixtures instead of real system
fi

# --- Collect data ---
status="OK"
errors=""
commands_run=0
commands_failed=0

collect_cmd() {
  local cmd="$1" output="$2" fallback="${3:-}"
  if command -v "$(echo "$cmd" | awk '{print $1}')" >/dev/null 2>&1; then
    eval "$cmd" > "$ARTIFACTS/$output" 2>/dev/null
    commands_run=$((commands_run + 1))
  elif [ -n "$fallback" ] && command -v "$(echo "$fallback" | awk '{print $1}')" >/dev/null 2>&1; then
    eval "$fallback" > "$ARTIFACTS/$output" 2>/dev/null
    commands_run=$((commands_run + 1))
  else
    commands_failed=$((commands_failed + 1))
  fi
}

# TODO: Add your collection commands here
# collect_cmd "ip addr show" "ip_addr.txt" "ifconfig -a"

# --- Fingerprint (Step 586) ---
fingerprint=""
if [ -d "$ARTIFACTS" ]; then
  fingerprint=$(find "$ARTIFACTS" -type f -exec sha256sum {} + 2>/dev/null | sha256sum 2>/dev/null | awk '{print $1}' || echo "")
fi

# --- Write result.json ---
artifacts_list=""
for f in "$ARTIFACTS"/*; do
  [ -f "$f" ] && artifacts_list="${artifacts_list}\"artifacts/$(basename "$f")\","
done
artifacts_list="[${artifacts_list%,}]"

output_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)

cat > "$RESULT" << REOF
{
  "schema_id": "result",
  "schema_version": "1",
  "collector_id": "${COLLECTOR_ID:-COLLECTOR_ID}",
  "status": "$status",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)",
  "finished_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)",
  "duration_ms": 0,
  "metrics": {
    "output_size_bytes": $output_bytes,
    "commands_run": $commands_run,
    "commands_skipped": 0,
    "commands_failed": $commands_failed
  },
  "data": {},
  "artifacts": $artifacts_list,
  "errors": [$errors],
  "fingerprint": "$fingerprint"
}
REOF

exit 0
