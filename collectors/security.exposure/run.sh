#!/bin/sh
WORKDIR="${COLLECTOR_WORKDIR:-.}"; ARTIFACTS="$WORKDIR/artifacts"; mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0

# Open ports on external interfaces
ss -tlnp 2>/dev/null | grep -E '0\.0\.0\.0|::|\*' > "$ARTIFACTS/external_listeners.txt" && cmds_run=$((cmds_run+1)) || true

# Firewall policy summary
iptables -L -n --line-numbers 2>/dev/null > "$ARTIFACTS/iptables_rules.txt" && cmds_run=$((cmds_run+1)) || true
iptables -L FORWARD -n -v 2>/dev/null > "$ARTIFACTS/forward_rules.txt" && cmds_run=$((cmds_run+1)) || true

# NAT rules
iptables -t nat -L -n 2>/dev/null > "$ARTIFACTS/nat_rules.txt" && cmds_run=$((cmds_run+1)) || true

# UPnP/port forwards (via ndm)
ndmc -c "show ip static" > "$ARTIFACTS/port_forwards.txt" 2>/dev/null || true
ndmc -c "show upnp" > "$ARTIFACTS/upnp.txt" 2>/dev/null || true

# SSH config
cat /opt/etc/config/dropbear.conf > "$ARTIFACTS/ssh_config.txt" 2>/dev/null || true

# Check for remote management
ndmc -c "show ip http" > "$ARTIFACTS/http_mgmt.txt" 2>/dev/null || true
ndmc -c "show ip telnet" > "$ARTIFACTS/telnet_mgmt.txt" 2>/dev/null || true

out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"security.exposure","status":"$status","metrics":{"commands_run":$cmds_run},"artifacts":[${arts%,}],"errors":[]}
REOF
exit 0
