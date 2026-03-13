#!/bin/sh
WORKDIR="${COLLECTOR_WORKDIR:-.}"; ARTIFACTS="$WORKDIR/artifacts"; mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0
cat /proc/interrupts > "$ARTIFACTS/interrupts.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
cat /proc/modules > "$ARTIFACTS/modules.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
cat /proc/cmdline > "$ARTIFACTS/cmdline.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
cat /proc/filesystems > "$ARTIFACTS/filesystems.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
cat /proc/vmstat > "$ARTIFACTS/vmstat.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
cat /proc/zoneinfo > "$ARTIFACTS/zoneinfo.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
# Sysctl network params
for p in net.ipv4.ip_forward net.ipv4.conf.all.rp_filter net.core.somaxconn net.netfilter.nf_conntrack_max net.ipv4.tcp_syncookies; do
  v=$(cat /proc/sys/$(echo $p | tr '.' '/') 2>/dev/null)
  [ -n "$v" ] && echo "$p = $v" >> "$ARTIFACTS/sysctl_net.txt"
done && cmds_run=$((cmds_run+1))
out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"system.kernel","status":"$status","metrics":{"commands_run":$cmds_run},"artifacts":[${arts%,}],"errors":[]}
REOF
exit 0
