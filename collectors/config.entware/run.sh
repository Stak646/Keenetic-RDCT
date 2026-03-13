#!/bin/sh
set -eu
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0; cmds_fail=0

if [ -d /opt/etc ]; then
  # Collect known config files
  for f in \
    /opt/etc/*.conf /opt/etc/*.cfg /opt/etc/*.ini /opt/etc/*.json \
    /opt/etc/config/* \
    /opt/etc/profile /opt/etc/passwd /opt/etc/group /opt/etc/shells \
    /opt/etc/entware_release /opt/etc/opkg.conf \
    /opt/etc/dnsmasq.conf /opt/etc/dnsmasq.d/* \
    /opt/etc/nginx/*.conf /opt/etc/nginx/conf.d/* \
    /opt/etc/crontab /opt/etc/crontabs/* \
    /opt/etc/nfqws*.conf /opt/etc/nfqws*/*.conf \
    /opt/etc/tpws*.conf \
    /opt/etc/opkg/*.conf \
    /opt/etc/ndm/*/*.sh \
    /opt/etc/init.d/S* \
    /opt/etc/hosts /opt/etc/resolv.conf \
    /opt/etc/shadow /opt/etc/gshadow \
    /opt/etc/ssl/openssl.cnf \
    /opt/etc/HydraRoute* /opt/etc/hydra* \
    /opt/etc/magitrickle* /opt/etc/MagiTrickle* \
    /opt/etc/awg* \
  ; do
    [ -f "$f" ] || continue
    [ ! -r "$f" ] && continue
    fsize=$(wc -c < "$f" 2>/dev/null || echo 0)
    [ "$fsize" -gt 524288 ] && continue  # skip >512KB
    rel=$(echo "$f" | sed 's|^/opt/etc/||' | tr '/' '_')
    cp "$f" "$ARTIFACTS/$rel" 2>/dev/null && cmds_run=$((cmds_run + 1))
  done

  # Also enumerate /opt/etc structure
  find /opt/etc -maxdepth 3 -type f 2>/dev/null | head -200 > "$ARTIFACTS/_file_list.txt" && cmds_run=$((cmds_run + 1))
else
  status="SKIP"
fi

out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"config.entware","status":"$status","started_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)","finished_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)","duration_ms":0,"metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run,"commands_failed":$cmds_fail},"data":{},"artifacts":[${arts%,}],"errors":[],"fingerprint":""}
REOF
exit 0
