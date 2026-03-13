#!/bin/sh
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0

# ARP table
cat /proc/net/arp > "$ARTIFACTS/arp_table.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true

# iw station dump
if command -v iw >/dev/null 2>&1; then
  for iface in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
    iw dev "$iface" station dump > "$ARTIFACTS/station_${iface}.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  done
fi

# Keenetic: ndmc for client list
if command -v ndmc >/dev/null 2>&1; then
  ndmc -c "show associations" > "$ARTIFACTS/ndm_associations.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  ndmc -c "show ip hotspot host" > "$ARTIFACTS/ndm_hotspot_hosts.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
fi

out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"wifi.clients","status":"$status","metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run},"artifacts":[${arts%,}],"errors":[]}
REOF
exit 0
