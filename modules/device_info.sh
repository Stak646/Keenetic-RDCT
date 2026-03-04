#!/bin/sh
# modules/device_info.sh — Collect basic device information
# Steps 491-493, 496

device_info_collect() {
  local workdir="$1"
  
  local model=$(cat /proc/cpuinfo 2>/dev/null | grep -i 'machine\|system' | head -1 | sed 's/.*: *//' || echo "unknown")
  local arch=$(uname -m 2>/dev/null || echo "unknown")
  local kernel=$(uname -r 2>/dev/null || echo "unknown")
  local hostname=$(cat /proc/sys/kernel/hostname 2>/dev/null || hostname 2>/dev/null || echo "unknown")
  local uptime=$(cat /proc/uptime 2>/dev/null | awk '{print $1}' || echo "0")
  local total_ram=$(grep '^MemTotal:' /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
  local cpu_count=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)
  
  # Step 496: Time sync check
  local time_ok="true"
  local year=$(date +%Y 2>/dev/null || echo 1970)
  [ "$year" -lt 2024 ] && time_ok="false"
  
  # Step 493: Redaction for Light/Medium
  local mode
  mode=$(config_get research_mode 2>/dev/null || echo "medium")
  local mac_addr=""
  if [ -f /sys/class/net/eth0/address ]; then
    mac_addr=$(cat /sys/class/net/eth0/address 2>/dev/null || echo "")
    if [ "$mode" = "light" ] || [ "$mode" = "medium" ]; then
      if [ "$(config_get privacy_hash_macs 2>/dev/null)" = "true" ]; then
        mac_addr=$(echo "$mac_addr" | sha256sum 2>/dev/null | cut -c1-12 || echo "redacted")
      fi
    fi
  fi
  
  # Device fingerprint
  local fp_input="${model}|${arch}|${kernel}|${mac_addr}"
  local fingerprint
  fingerprint=$(echo "$fp_input" | sha256sum 2>/dev/null | cut -c1-16 || echo "unknown")
  echo "$fingerprint" > "$workdir/device_fingerprint"
  
  cat > "$workdir/device.json" << DEOF
{
  "model": "$model",
  "arch": "$arch",
  "kernel": "$kernel",
  "hostname": "$hostname",
  "uptime_s": $uptime,
  "total_ram_kb": $total_ram,
  "cpu_count": $cpu_count,
  "mac_hash": "$mac_addr",
  "fingerprint": "$fingerprint",
  "time_sync_ok": $time_ok,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
}
DEOF
}
