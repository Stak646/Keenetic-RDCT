#!/bin/sh
set -eu
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0; cmds_fail=0

# BusyBox ps: use 'ps w' or 'ps -w' (not aux)
ps w 2>/dev/null > "$ARTIFACTS/ps_list.txt" && cmds_run=$((cmds_run+1)) || \
  ps 2>/dev/null > "$ARTIFACTS/ps_list.txt" && cmds_run=$((cmds_run+1)) || cmds_fail=$((cmds_fail+1))

# Process count
wc -l < "$ARTIFACTS/ps_list.txt" > "$ARTIFACTS/process_count.txt" 2>/dev/null

# Top CPU/mem consumers (if top available in batch mode)
top -bn1 2>/dev/null | head -30 > "$ARTIFACTS/top_snapshot.txt" && cmds_run=$((cmds_run+1)) || true

# /proc data
for f in /proc/loadavg /proc/stat /proc/vmstat /proc/uptime; do
  [ -r "$f" ] && cp "$f" "$ARTIFACTS/$(basename $f).txt" 2>/dev/null && cmds_run=$((cmds_run+1))
done

# Per-process memory (top consumers)
for pid in $(ls /proc/ 2>/dev/null | grep '^[0-9]*$' | head -100); do
  [ -r "/proc/$pid/status" ] || continue
  name=$(grep '^Name:' "/proc/$pid/status" 2>/dev/null | awk '{print $2}')
  vmrss=$(grep '^VmRSS:' "/proc/$pid/status" 2>/dev/null | awk '{print $2}')
  [ -n "$vmrss" ] && echo "$vmrss $pid $name"
done 2>/dev/null | sort -rn | head -20 > "$ARTIFACTS/top_memory.txt" && cmds_run=$((cmds_run+1))

out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"system.proc_snapshot","status":"$status","metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run,"commands_failed":$cmds_fail},"artifacts":[${arts%,}],"errors":[]}
REOF
exit 0
