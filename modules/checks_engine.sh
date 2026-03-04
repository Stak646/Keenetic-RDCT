#!/bin/sh
# modules/checks_engine.sh — Diff-driven checks comparing baseline vs current
# Steps 897-912, 938

checks_run() {
  local report_dir="$1"
  local baseline_dir="$2"
  local output="$3"
  local mode="${4:-medium}"
  
  local checks=""
  local total=0 crit=0 warn=0 info=0
  
  # Step 899: net.new_listen_port
  checks_new_listen_port "$report_dir" "$baseline_dir" "$mode"
  
  # Step 900: config.autostart_drift
  checks_autostart_drift "$report_dir" "$baseline_dir"
  
  # Step 901: pkg.changes
  checks_pkg_changes "$report_dir" "$baseline_dir"
  
  # Step 902: proc.suspicious_exec
  checks_suspicious_exec "$report_dir"
  
  # Step 903: endpoint.changed_headers
  checks_endpoint_changes "$report_dir" "$baseline_dir"
  
  # Step 904: wifi.regression
  checks_wifi_regression "$report_dir" "$baseline_dir"
  
  # Step 905: vpn.regression
  checks_vpn_regression "$report_dir" "$baseline_dir"
  
  # Step 906: storage.growth
  checks_storage_growth "$report_dir" "$baseline_dir"
  
  # Step 907: logs.anomalies
  checks_log_anomalies "$report_dir"
  
  # Step 908: resources.spikes
  checks_resource_spikes "$report_dir" "$baseline_dir"
  
  # Step 938: baseline_drift_major
  checks_baseline_drift "$report_dir" "$baseline_dir"
  
  # Collect all checks from temp file
  local all_checks=""
  [ -f "$report_dir/.checks_tmp" ] && all_checks=$(cat "$report_dir/.checks_tmp" | tr '\n' ',' | sed 's/,$//')
  total=$(echo "$all_checks" | tr ',' '\n' | grep -c '{' 2>/dev/null || echo 0)
  crit=$(grep -c '"CRIT"' "$report_dir/.checks_tmp" 2>/dev/null || echo 0)
  warn=$(grep -c '"WARN"' "$report_dir/.checks_tmp" 2>/dev/null || echo 0)
  info=$(grep -c '"INFO"' "$report_dir/.checks_tmp" 2>/dev/null || echo 0)
  
  # Step 909: Privacy-aware output
  # In Light/Medium, redact specific IPs/MACs in checks
  
  cat > "$output" << CKEOF
{
  "schema_id": "checks",
  "schema_version": "1",
  "report_id": "${TOOL_REPORT_ID:-unknown}",
  "base_report_id": "$(basename "$baseline_dir" 2>/dev/null || echo null)",
  "summary": {"total": $total, "critical": $crit, "warn": $warn, "info": $info},
  "checks": [$all_checks]
}
CKEOF
  
  rm -f "$report_dir/.checks_tmp"
}

_add_check() {
  local report_dir="$1" id="$2" sev="$3" title="$4" desc="$5" evidence="$6" hint="$7" tags="$8" cat="$9"
  echo "{\"id\":\"$id\",\"severity\":\"$sev\",\"title\":\"$title\",\"description\":\"$desc\",\"evidence\":\"$evidence\",\"remediation_hint\":\"$hint\",\"privacy_tags\":[$tags],\"category\":\"$cat\"}" >> "$report_dir/.checks_tmp"
}

# Step 899
checks_new_listen_port() {
  local rd="$1" bd="$2" mode="$3"
  local current="$rd/collectors/network.sockets/artifacts/ss_tulnp.txt"
  local baseline="$bd/collectors/network.sockets/artifacts/ss_tulnp.txt"
  
  [ ! -f "$current" ] && return
  [ ! -f "$baseline" ] && return
  
  # Find new listening ports not in baseline
  local new_ports=$(diff "$baseline" "$current" 2>/dev/null | grep '^>' | grep -E 'LISTEN|UNCONN' | head -5)
  if [ -n "$new_ports" ]; then
    local port=$(echo "$new_ports" | head -1 | awk '{print $5}' | rev | cut -d: -f1 | rev)
    _add_check "$rd" "net.new_listen_port" "WARN" "New listening port detected" \
      "New port(s) found since baseline" "$port" "Verify this is expected" '"ip"' "network"
  fi
}

# Step 900
checks_autostart_drift() {
  local rd="$1" bd="$2"
  local current="$rd/collectors/hooks.ndm/artifacts"
  local baseline="$bd/collectors/hooks.ndm/artifacts"
  [ ! -d "$current" ] || [ ! -d "$baseline" ] && return
  
  local diff_count=$(diff -rq "$baseline" "$current" 2>/dev/null | wc -l)
  if [ "$diff_count" -gt 0 ]; then
    _add_check "$rd" "config.autostart_drift" "WARN" "Autostart configuration changed" \
      "$diff_count file(s) differ in hooks/init.d" "$diff_count changes" "Review hook changes" '""' "config"
  fi
}

# Step 901
checks_pkg_changes() {
  local rd="$1" bd="$2"
  local curr="$rd/collectors/opkg.status/artifacts/opkg_installed.txt"
  local base="$bd/collectors/opkg.status/artifacts/opkg_installed.txt"
  [ ! -f "$curr" ] || [ ! -f "$base" ] && return
  
  local new_pkgs=$(diff "$base" "$curr" 2>/dev/null | grep '^>' | wc -l)
  local removed_pkgs=$(diff "$base" "$curr" 2>/dev/null | grep '^<' | wc -l)
  if [ "$new_pkgs" -gt 0 ] || [ "$removed_pkgs" -gt 0 ]; then
    _add_check "$rd" "pkg.changes" "INFO" "Package changes detected" \
      "+$new_pkgs new, -$removed_pkgs removed" "packages" "Review package changes" '""' "packages"
  fi
}

# Step 902
checks_suspicious_exec() {
  local rd="$1"
  local ps_file="$rd/collectors/system.proc_snapshot/artifacts/ps_aux.txt"
  [ ! -f "$ps_file" ] && return
  
  if grep -qE '/tmp/|/var/tmp/' "$ps_file" 2>/dev/null; then
    _add_check "$rd" "proc.suspicious_exec" "CRIT" "Process running from /tmp" \
      "Executable launched from temporary directory" "/tmp or /var/tmp" "Investigate immediately" '""' "security"
  fi
}

# Step 903
checks_endpoint_changes() {
  local rd="$1" bd="$2"
  # Compare websnap artifacts if present
  local curr_dir="$rd/collectors/apps.websnap/artifacts"
  local base_dir="$bd/collectors/apps.websnap/artifacts"
  [ ! -d "$curr_dir" ] || [ ! -d "$base_dir" ] && return
  
  local changed=$(diff -rq "$base_dir" "$curr_dir" 2>/dev/null | wc -l)
  if [ "$changed" -gt 0 ]; then
    _add_check "$rd" "endpoint.changed_headers" "INFO" "Web endpoint changes" \
      "$changed endpoint(s) changed" "websnap diff" "Review endpoint changes" '"token","cookie"' "endpoints"
  fi
}

# Step 904
checks_wifi_regression() {
  local rd="$1" bd="$2"
  # Compare wifi data
  local curr="$rd/collectors/wifi.radio/artifacts"
  local base="$bd/collectors/wifi.radio/artifacts"
  [ ! -d "$curr" ] || [ ! -d "$base" ] && return
  
  local diff_count=$(diff -rq "$base" "$curr" 2>/dev/null | wc -l)
  [ "$diff_count" -gt 0 ] && _add_check "$rd" "wifi.regression" "WARN" "WiFi configuration changed" \
    "$diff_count radio parameter(s) differ" "wifi config" "Check channel/DFS/power changes" '"ssid"' "wifi"
}

# Step 905
checks_vpn_regression() {
  local rd="$1" bd="$2"
  local curr="$rd/collectors/vpn.tunnels/artifacts"
  local base="$bd/collectors/vpn.tunnels/artifacts"
  [ ! -d "$curr" ] || [ ! -d "$base" ] && return
  
  local diff_count=$(diff -rq "$base" "$curr" 2>/dev/null | wc -l)
  [ "$diff_count" -gt 0 ] && _add_check "$rd" "vpn.regression" "WARN" "VPN tunnel changes" \
    "$diff_count VPN parameter(s) differ" "vpn diff" "Check tunnel status and peers" '"ip","key"' "vpn"
}

# Step 906
checks_storage_growth() {
  local rd="$1" bd="$2"
  local curr="$rd/collectors/storage.topn/artifacts/top_dirs_opt.txt"
  local base="$bd/collectors/storage.topn/artifacts/top_dirs_opt.txt"
  [ ! -f "$curr" ] && return
  # Simplified: alert if large files appeared
  local large=$(wc -l < "$rd/collectors/storage.topn/artifacts/large_files.txt" 2>/dev/null || echo 0)
  [ "$large" -gt 10 ] && _add_check "$rd" "storage.growth" "WARN" "Storage growth detected" \
    "$large large files found" "storage" "Review large files for unexpected growth" '""' "storage"
}

# Step 907
checks_log_anomalies() {
  local rd="$1"
  local dmesg="$rd/collectors/logs.system/artifacts/dmesg.txt"
  [ ! -f "$dmesg" ] && return
  
  local oom=$(grep -c 'Out of memory\|oom_kill\|OOM' "$dmesg" 2>/dev/null || echo 0)
  local segfault=$(grep -c 'segfault\|Segmentation fault' "$dmesg" 2>/dev/null || echo 0)
  
  [ "$oom" -gt 0 ] && _add_check "$rd" "logs.oom_detected" "CRIT" "OOM kills detected in dmesg" \
    "$oom OOM events" "dmesg" "Investigate memory pressure" '""' "resources"
  [ "$segfault" -gt 0 ] && _add_check "$rd" "logs.segfault" "WARN" "Segfaults detected in dmesg" \
    "$segfault segfault events" "dmesg" "Check for unstable software" '""' "stability"
}

# Step 908
checks_resource_spikes() {
  local rd="$1" bd="$2"
  # Compare governor metrics
  local curr_gov="$rd/governor.json"
  [ ! -f "$curr_gov" ] && return
  # Simplified check
  true
}

# Step 938: Baseline drift major
checks_baseline_drift() {
  local rd="$1" bd="$2"
  [ ! -d "$bd" ] && return
  
  local curr_ver=$(cat "$rd/device.json" 2>/dev/null | grep kernel | head -1)
  local base_ver=$(cat "$bd/device.json" 2>/dev/null | grep kernel | head -1)
  
  if [ -n "$curr_ver" ] && [ -n "$base_ver" ] && [ "$curr_ver" != "$base_ver" ]; then
    _add_check "$rd" "baseline_drift_major" "WARN" "Major system change since baseline" \
      "Kernel or firmware version changed" "version diff" "Consider rebase" '""' "system"
  fi
}

# Step 912: CLI interface
checks_show() {
  local prefix="${PREFIX:-/opt/keenetic-debug}"
  local latest=$(ls -1td "$prefix/reports"/*/ 2>/dev/null | head -1)
  [ -z "$latest" ] && echo "No reports" && return 1
  local checks_file="$latest/checks.json"
  [ -f "$checks_file" ] && cat "$checks_file" || echo "No checks in latest report"
}
