#!/bin/sh
set -eu
WORKDIR="${COLLECTOR_WORKDIR:-.}"
ARTIFACTS="$WORKDIR/artifacts"
mkdir -p "$ARTIFACTS"
status="OK"; cmds_run=0; cmds_fail=0

c() { local cmd="$1" out="$2"; eval "$cmd" > "$ARTIFACTS/$out" 2>/dev/null && cmds_run=$((cmds_run+1)) || cmds_fail=$((cmds_fail+1)); }
r() { [ -r "$1" ] && cp "$1" "$ARTIFACTS/$2" 2>/dev/null && cmds_run=$((cmds_run+1)) || true; }

c "uname -a" "uname.txt"
c "cat /proc/version" "proc_version.txt"
r "/proc/cpuinfo" "proc_cpuinfo.txt"
r "/proc/meminfo" "proc_meminfo.txt"
r "/proc/loadavg" "proc_loadavg.txt"
r "/proc/uptime" "proc_uptime.txt"
r "/proc/stat" "proc_stat.txt"
r "/proc/mounts" "proc_mounts.txt"
r "/proc/interrupts" "proc_interrupts.txt"
r "/proc/modules" "proc_modules.txt"
r "/proc/cmdline" "proc_cmdline.txt"
r "/proc/filesystems" "proc_filesystems.txt"
c "ps w" "ps.txt"
c "df -h" "df.txt"
c "mount" "mount.txt"
c "dmesg" "dmesg_full.txt"
c "dmesg | tail -100" "dmesg_tail.txt"
c "date" "date.txt"
c "uptime" "uptime_human.txt"
c "free" "free.txt"
c "cat /etc/TZ" "timezone.txt"

# Keenetic model
c "ndmc -c 'show version'" "ndm_version.txt"
c "ndmc -c 'show interface'" "ndm_interfaces.txt"

# NTP status
c "ndmc -c 'show clock'" "ndm_clock.txt"

# Sysctl network params
c "cat /proc/sys/net/ipv4/ip_forward" "ip_forward.txt"
c "cat /proc/sys/net/netfilter/nf_conntrack_max" "conntrack_max.txt"

out_bytes=$(du -sb "$ARTIFACTS" 2>/dev/null | awk '{print $1}' || echo 0)
arts=""; for f in "$ARTIFACTS"/*; do [ -f "$f" ] && arts="${arts}\"artifacts/$(basename "$f")\","; done
cat > "$WORKDIR/result.json" << REOF
{"schema_id":"result","schema_version":"1","collector_id":"system.base","status":"$status","started_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)","finished_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)","duration_ms":0,"metrics":{"output_size_bytes":$out_bytes,"commands_run":$cmds_run,"commands_failed":$cmds_fail},"data":{},"artifacts":[${arts%,}],"errors":[],"fingerprint":""}
REOF
exit 0
