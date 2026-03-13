#!/bin/sh
WORKDIR="${COLLECTOR_WORKDIR:-.}"; ARTIFACTS="$WORKDIR/artifacts"; mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0
cat /proc/net/dev > "$ARTIFACTS/proc_net_dev.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
ip -s link show > "$ARTIFACTS/ip_link_stats.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
ip addr show > "$ARTIFACTS/ip_addr_full.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
# VLAN info
ip -d link show type vlan > "$ARTIFACTS/vlans.txt" 2>/dev/null || true
# Bridge info
ip -d link show type bridge > "$ARTIFACTS/bridges.txt" 2>/dev/null || true
# Interface errors/drops summary
awk 'NR>2{gsub(/:/, " "); printf "%-12s rx_bytes=%-12s rx_drop=%-6s tx_bytes=%-12s tx_drop=%-6s\n",$1,$2,$5,$10,$13}' /proc/net/dev > "$ARTIFACTS/interface_summary.txt" 2>/dev/null || true
out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"network.interfaces","status":"$status","metrics":{"commands_run":$cmds_run},"artifacts":[${arts%,}],"errors":[]}
REOF
exit 0
