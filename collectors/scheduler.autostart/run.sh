#!/bin/sh
WORKDIR="${COLLECTOR_WORKDIR:-.}"; ARTIFACTS="$WORKDIR/artifacts"; mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0
# Cron
crontab -l > "$ARTIFACTS/crontab.txt" 2>/dev/null || true
cat /opt/etc/crontab > "$ARTIFACTS/etc_crontab.txt" 2>/dev/null || true
ls -la /opt/etc/cron.d/ > "$ARTIFACTS/cron_d_list.txt" 2>/dev/null || true
# Init.d full inventory
for f in /opt/etc/init.d/S*; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  echo "=== $name ===" >> "$ARTIFACTS/initd_contents.txt"
  head -20 "$f" >> "$ARTIFACTS/initd_contents.txt" 2>/dev/null
  echo "" >> "$ARTIFACTS/initd_contents.txt"
  cmds_run=$((cmds_run+1))
done
# NDM scheduled tasks
ndmc -c "show schedule" > "$ARTIFACTS/ndm_schedule.txt" 2>/dev/null || true
out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"scheduler.autostart","status":"$status","metrics":{"commands_run":$cmds_run},"artifacts":[${arts%,}],"errors":[]}
REOF
exit 0
