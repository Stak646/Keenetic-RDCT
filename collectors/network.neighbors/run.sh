#!/bin/sh
WORKDIR="${COLLECTOR_WORKDIR:-.}"; ARTIFACTS="$WORKDIR/artifacts"; mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0; cmds_fail=0
ip neigh show > "$ARTIFACTS/ip_neigh.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
cat /proc/net/arp > "$ARTIFACTS/proc_arp.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
ip -6 neigh show > "$ARTIFACTS/ip6_neigh.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
# Bridge FDB
ip link show type bridge > "$ARTIFACTS/bridges.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"network.neighbors","status":"$status","metrics":{"commands_run":$cmds_run},"artifacts":[${arts%,}],"errors":[]}
REOF
exit 0
