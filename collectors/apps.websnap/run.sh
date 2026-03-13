#!/bin/sh
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0; cmds_fail=0; found=0

# Scan common local web panel ports
for port in 80 8080 8443 443 3000 9090 90 8888 5000; do
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 3 --connect-timeout 2 -o "$ARTIFACTS/websnap_${port}.html" "http://127.0.0.1:$port/" 2>/dev/null
    if [ -s "$ARTIFACTS/websnap_${port}.html" ]; then
      cmds_run=$((cmds_run+1)); found=$((found+1))
      # Get headers too
      curl -fsS --max-time 3 -I "http://127.0.0.1:$port/" > "$ARTIFACTS/headers_${port}.txt" 2>/dev/null || true
    else
      rm -f "$ARTIFACTS/websnap_${port}.html"
    fi
  fi
done

[ $found -eq 0 ] && echo "No local web panels found" > "$ARTIFACTS/no_panels.txt"

out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"apps.websnap","status":"$status","metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run,"panels_found":$found},"artifacts":[${arts%,}],"errors":[]}
REOF
exit 0
