#!/bin/sh
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0; cmds_fail=0

# iptables-save or iptables -L
if command -v iptables-save >/dev/null 2>&1; then
  iptables-save > "$ARTIFACTS/iptables_save.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
elif command -v iptables >/dev/null 2>&1; then
  iptables -L -n -v > "$ARTIFACTS/iptables_rules.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  iptables -t nat -L -n > "$ARTIFACTS/iptables_nat.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
fi

# ip6tables
if command -v ip6tables-save >/dev/null 2>&1; then
  ip6tables-save > "$ARTIFACTS/ip6tables_save.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
elif command -v ip6tables >/dev/null 2>&1; then
  ip6tables -L -n -v > "$ARTIFACTS/ip6tables_rules.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
fi

# nft if available
command -v nft >/dev/null 2>&1 && nft list ruleset > "$ARTIFACTS/nft_ruleset.txt" 2>/dev/null || true

# Keenetic firewall via ndm
command -v ndmc >/dev/null 2>&1 && ndmc -c "show ip nat" > "$ARTIFACTS/ndm_nat.txt" 2>/dev/null || true

out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"network.firewall","status":"$status","metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run,"commands_failed":$cmds_fail},"artifacts":[${arts%,}],"errors":[]}
REOF
exit 0
