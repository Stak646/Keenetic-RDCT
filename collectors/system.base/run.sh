#!/bin/sh
# collectors/system.base/run.sh
# Collects basic system information: CPU, memory, load, uptime, mounts, processes
set -eu

COLLECTOR_ID="system.base"
WORK_DIR="${WORK_DIR:-.}"
RESEARCH_MODE="${RESEARCH_MODE:-medium}"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)"

check_cmd() { command -v "$1" >/dev/null 2>&1; }

mkdir -p "$WORK_DIR/artifacts"

# --- Collect data ---
STATUS="OK"
REASON=""
DATA_PARTS=""

# uname
if check_cmd uname; then
  uname -a > "$WORK_DIR/artifacts/uname.txt" 2>/dev/null || true
fi

# /proc files
for proc_file in cpuinfo meminfo loadavg uptime version mounts; do
  src="/proc/$proc_file"
  if [ -r "$src" ]; then
    cp "$src" "$WORK_DIR/artifacts/proc_${proc_file}.txt" 2>/dev/null || true
  fi
done

# ps snapshot
if check_cmd ps; then
  ps -ef > "$WORK_DIR/artifacts/ps.txt" 2>/dev/null || \
  ps w > "$WORK_DIR/artifacts/ps.txt" 2>/dev/null || true
fi

# df (disk usage)
if check_cmd df; then
  df -h > "$WORK_DIR/artifacts/df.txt" 2>/dev/null || \
  df > "$WORK_DIR/artifacts/df.txt" 2>/dev/null || true
fi

# mount
if check_cmd mount; then
  mount > "$WORK_DIR/artifacts/mount.txt" 2>/dev/null || true
fi

# dmesg (if accessible and mode >= medium)
if [ "$RESEARCH_MODE" != "light" ]; then
  if check_cmd dmesg; then
    dmesg 2>/dev/null | tail -200 > "$WORK_DIR/artifacts/dmesg_tail.txt" 2>/dev/null || true
  fi
fi

# Calculate output size
OUTPUT_SIZE=0
if check_cmd du; then
  OUTPUT_SIZE=$(du -sb "$WORK_DIR/artifacts" 2>/dev/null | cut -f1 || echo 0)
fi

FINISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)"

# --- Build artifact list ---
ARTIFACTS_JSON="["
first=true
for f in "$WORK_DIR"/artifacts/*; do
  [ -f "$f" ] || continue
  fname=$(basename "$f")
  fsize=$(wc -c < "$f" 2>/dev/null | tr -d ' ' || echo 0)
  if [ "$first" = true ]; then first=false; else ARTIFACTS_JSON="$ARTIFACTS_JSON,"; fi
  ARTIFACTS_JSON="$ARTIFACTS_JSON{\"path\":\"artifacts/$fname\",\"size_bytes\":$fsize}"
done
ARTIFACTS_JSON="$ARTIFACTS_JSON]"

# --- Write result.json ---
cat > "$WORK_DIR/result.json" << RESULT_EOF
{
  "schema_id": "keenetic-debug.collector.result",
  "schema_version": 1,
  "collector_id": "$COLLECTOR_ID",
  "status": "$STATUS",
  "reason": "$REASON",
  "started_at": "$STARTED_AT",
  "finished_at": "$FINISHED_AT",
  "duration_ms": 0,
  "output_size_bytes": $OUTPUT_SIZE,
  "data": {},
  "artifacts": $ARTIFACTS_JSON,
  "fingerprint": {}
}
RESULT_EOF

exit 0
