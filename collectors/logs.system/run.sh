#!/bin/sh
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0

# dmesg (full + filtered)
dmesg > "$ARTIFACTS/dmesg.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
dmesg | grep -iE 'error|warn|fail|oom|segfault|panic|usb' > "$ARTIFACTS/dmesg_errors.txt" 2>/dev/null || true

# System logs
MAX_KB=512
for logf in /var/log/syslog /var/log/messages /opt/var/log/messages /tmp/syslog.log; do
  if [ -r "$logf" ]; then
    tail -c $((MAX_KB*1024)) "$logf" > "$ARTIFACTS/$(basename $logf).txt" 2>/dev/null && cmds_run=$((cmds_run+1))
  fi
done

# Keenetic system log
if command -v ndmc >/dev/null 2>&1; then
  ndmc -c "show log" > "$ARTIFACTS/ndm_log.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
fi

# Last login info
last > "$ARTIFACTS/last_logins.txt" 2>/dev/null || true

out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"logs.system","status":"$status","metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run},"artifacts":[${arts%,}],"errors":[]}
REOF
exit 0
