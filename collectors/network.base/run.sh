#!/bin/sh
set -eu
BASE_DIR="${TOOL_BASE_DIR:-/opt/keenetic-debug}"
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
RESULT="$WORKDIR/result.json"
mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0; cmds_fail=0; skipped=""

collect() { local cmd="$1" out="$2" fb="${3:-}"; local t=$(echo "$cmd"|awk '{print $1}'); if command -v "$t" >/dev/null 2>&1; then eval "$cmd" > "$ARTIFACTS/$out" 2>/dev/null && cmds_run=$((cmds_run+1)) || cmds_fail=$((cmds_fail+1)); elif [ -n "$fb" ]; then local ft=$(echo "$fb"|awk '{print $1}'); if command -v "$ft" >/dev/null 2>&1; then eval "$fb" > "$ARTIFACTS/$out" 2>/dev/null && cmds_run=$((cmds_run+1)); else cmds_fail=$((cmds_fail+1)); fi; else cmds_fail=$((cmds_fail+1)); fi; }

collect "ip addr show" "ip_addr.txt" "ifconfig -a"
collect "ip link show" "ip_link.txt"
collect "ip route show table all" "ip_route.txt" "route -n"
collect "ip rule show" "ip_rules.txt"
collect "ip neigh show" "ip_neigh.txt" "arp -an"
[ -r /proc/net/dev ] && cat /proc/net/dev > "$ARTIFACTS/proc_net_dev.txt" 2>/dev/null && cmds_run=$((cmds_run+1))
[ -r /etc/resolv.conf ] && cp /etc/resolv.conf "$ARTIFACTS/resolv.conf" 2>/dev/null

out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
fp=""; command -v sha256sum >/dev/null 2>&1 && fp=$(find "$ARTIFACTS" -type f -exec sha256sum {} + 2>/dev/null | sha256sum | awk '{print $1}')

cat > "$RESULT" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"network.base","status":"$status","started_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)","finished_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)","duration_ms":0,"metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run,"commands_skipped":0,"commands_failed":$cmds_fail},"data":{},"artifacts":[${arts%,}],"errors":[],"fingerprint":"$fp"}
REOF
exit 0
