#!/bin/sh
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0; cmds_fail=0

# Try ss first, fall back to netstat
if command -v ss >/dev/null 2>&1; then
  ss -tulnp > "$ARTIFACTS/ss_tulnp.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  ss -s > "$ARTIFACTS/ss_stats.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
elif command -v netstat >/dev/null 2>&1; then
  netstat -tulnp > "$ARTIFACTS/ss_tulnp.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  netstat -s > "$ARTIFACTS/ss_stats.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
else
  cmds_fail=$((cmds_fail+1))
fi

out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"network.sockets","status":"$status","metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run,"commands_failed":$cmds_fail},"artifacts":[${arts%,}],"errors":[]}
REOF
exit 0
