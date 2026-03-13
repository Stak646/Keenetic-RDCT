#!/bin/sh
set -eu
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0; cmds_fail=0

# Inode usage
df -i 2>/dev/null > "$ARTIFACTS/inode_usage.txt" && cmds_run=$((cmds_run+1)) || true

# Top directories in /opt
du -k /opt/* 2>/dev/null | sort -rn | head -30 > "$ARTIFACTS/top_dirs_opt.txt" && cmds_run=$((cmds_run+1)) || true

# Large files (>1MB)
find /opt -maxdepth 5 -type f -size +1024k 2>/dev/null | head -50 | while read -r f; do
  sz=$(ls -la "$f" 2>/dev/null | awk '{print $5}')
  echo "$sz $f"
done | sort -rn > "$ARTIFACTS/large_files.txt" && cmds_run=$((cmds_run+1)) || true

# Disk usage summary
df -k 2>/dev/null > "$ARTIFACTS/disk_usage.txt" && cmds_run=$((cmds_run+1)) || true

# /opt total
du -sk /opt 2>/dev/null > "$ARTIFACTS/opt_total.txt" && cmds_run=$((cmds_run+1)) || true

out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"storage.topn","status":"$status","started_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)","finished_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)","duration_ms":0,"metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run,"commands_failed":$cmds_fail},"data":{},"artifacts":[${arts%,}],"errors":[],"fingerprint":""}
REOF
exit 0
