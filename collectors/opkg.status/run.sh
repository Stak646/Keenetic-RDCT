#!/bin/sh
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0; cmds_fail=0

if command -v opkg >/dev/null 2>&1; then
  opkg list-installed > "$ARTIFACTS/opkg_installed.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  opkg status > "$ARTIFACTS/opkg_status.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  opkg print-architecture > "$ARTIFACTS/opkg_arch.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  cat /opt/etc/opkg.conf > "$ARTIFACTS/opkg_conf.txt" 2>/dev/null && cmds_run=$((cmds_run+1)) || true
  # List all opkg repos
  cat /opt/etc/opkg/*.conf > "$ARTIFACTS/opkg_repos.txt" 2>/dev/null || true
  # Package count
  wc -l < "$ARTIFACTS/opkg_installed.txt" > "$ARTIFACTS/package_count.txt" 2>/dev/null || true
else
  status="SKIP"
fi

out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"opkg.status","status":"$status","metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run,"commands_failed":$cmds_fail},"artifacts":[${arts%,}],"errors":[]}
REOF
exit 0
