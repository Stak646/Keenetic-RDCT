#!/bin/sh
set -eu
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0; cmds_fail=0

# Denylist: binaries, libraries, caches, our own tool, large blobs
EXCLUDE_PATTERNS='\.pyc$|\.pyo$|\.so\.|\.so$|\.a$|\.o$|/lib/python|/share/zoneinfo|/share/terminfo|/share/locale|/share/i18n|/lib/opkg|/var/opkg|/var/cache|/var/run|/var/lock|/lib/ld-|/lib/libc|/lib/libm|/lib/libdl|/lib/libpthread|/lib/librt|/lib/libnsl|/lib/libresolv|/lib/libcrypt|/lib/libutil|/lib/libgcc|/lib/libstdc|/lib/libssl|/lib/libcrypto|/lib/libcurl|/lib/libpython|/lib/libsqlite|/lib/libreadline|/lib/libncurses|/lib/libffi|/lib/libbz2|/lib/liblzma|/lib/libuuid|/lib/libz\.|/bin/busybox|/bin/python|/bin/curl|/bin/jq|/bin/opkg|/sbin/|/usr/bin/|/usr/lib/|keenetic-debug/tmp|keenetic-debug/reports|keenetic-debug/run|keenetic-debug/logs|\.tar\.gz$|\.zip$|\.gz$|\.bak$'

MAX_FILES=500
MAX_FILE_SIZE=1048576  # 1MB per file
count=0

find /opt -maxdepth 6 -type f 2>/dev/null | grep -vE "$EXCLUDE_PATTERNS" | head -$MAX_FILES | while read -r f; do
  [ ! -r "$f" ] && continue
  fsize=$(wc -c < "$f" 2>/dev/null || echo 0)
  [ "$fsize" -gt "$MAX_FILE_SIZE" ] && continue
  # Skip binary files (check first bytes)
  if file "$f" 2>/dev/null | grep -qiE 'ELF|executable|shared object|archive'; then
    continue
  fi
  rel=$(echo "$f" | sed 's|^/opt/||' | tr '/' '_')
  cp "$f" "$ARTIFACTS/$rel" 2>/dev/null && cmds_run=$((cmds_run + 1))
  count=$((count + 1))
done

out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"mirror.full","status":"$status","started_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)","finished_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)","duration_ms":0,"metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run,"commands_skipped":0,"commands_failed":$cmds_fail},"data":{},"artifacts":[${arts%,}],"errors":[],"fingerprint":""}
REOF
exit 0
