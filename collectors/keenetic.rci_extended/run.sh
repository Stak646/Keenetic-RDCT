#!/bin/sh
WORKDIR="${COLLECTOR_WORKDIR:-.}"; ARTIFACTS="$WORKDIR/artifacts"; mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0
if command -v ndmc >/dev/null 2>&1; then
  for q in "show running-config" "show ip route" "show ip name-server" "show interface stat" \
           "show ip dhcp pool" "show ip dhcp binding" "show ip hotspot host" \
           "show clock" "show log" "show media"; do
    safe=$(echo "$q" | tr ' ' '_')
    ndmc -c "$q" > "$ARTIFACTS/rci_${safe}.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  done
else
  status="SKIP"
fi
out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"keenetic.rci_extended","status":"$status","metrics":{"commands_run":$cmds_run},"artifacts":[${arts%,}],"errors":[]}
REOF
exit 0
