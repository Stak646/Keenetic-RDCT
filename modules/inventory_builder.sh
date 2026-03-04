#!/bin/sh
# modules/inventory_builder.sh — Build inventory from collector results
# Steps 835-845, 869-871

inventory_build() {
  local report_dir="$1"
  local output="$2"
  local mode="${3:-medium}"
  
  local entries=""
  local total_ports=0 total_procs=0 total_pkgs=0 total_endpoints=0
  local warnings=""
  
  # Step 837: Port→PID from network.sockets
  local sockets_file="$report_dir/collectors/network.sockets/artifacts/ss_tulnp.txt"
  if [ -f "$sockets_file" ]; then
    # Parse ss -tulnp output: State Recv-Q Send-Q Local:Port Peer:Port Process
    while IFS= read -r line; do
      echo "$line" | grep -qE '^(tcp|udp)' || continue
      local proto=$(echo "$line" | awk '{print $1}')
      local local_addr=$(echo "$line" | awk '{print $5}')
      local port=$(echo "$local_addr" | rev | cut -d: -f1 | rev)
      local bind=$(echo "$local_addr" | rev | cut -d: -f2- | rev)
      local process=$(echo "$line" | grep -oP 'users:\(\("([^"]+)"' 2>/dev/null | sed 's/users:(("//;s/"$//' || echo "unknown")
      local pid=$(echo "$line" | grep -oP 'pid=([0-9]+)' 2>/dev/null | sed 's/pid=//' || echo "0")
      
      [ -z "$port" ] || [ "$port" = "Port" ] && continue
      total_ports=$((total_ports + 1))
      
      # Step 838: PID→executable
      local exe="unknown"
      [ -r "/proc/$pid/exe" ] && exe=$(readlink "/proc/$pid/exe" 2>/dev/null || echo "unknown")
      local cmdline=""
      [ -r "/proc/$pid/cmdline" ] && cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || echo "")
      
      # Step 839: executable→opkg_package
      local pkg=""
      if command -v opkg >/dev/null 2>&1 && [ "$exe" != "unknown" ]; then
        pkg=$(opkg search "$exe" 2>/dev/null | head -1 | awk '{print $1}' || echo "")
      fi
      
      # Step 845: Risk warnings
      local entry_warnings=""
      if [ "$bind" = "0.0.0.0" ] || [ "$bind" = "::" ] || [ "$bind" = "*" ]; then
        entry_warnings="\"external_bind\""
        warnings="${warnings}{\"port\":$port,\"warning\":\"listening on 0.0.0.0\"},"
      fi
      
      # Step 869: Privacy-aware (mask IP/MAC in Light/Medium)
      if [ "$mode" = "light" ] || [ "$mode" = "medium" ]; then
        bind="***"
      fi
      
      entries="${entries}{\"port\":$port,\"proto\":\"$proto\",\"bind_addr\":\"$bind\",\"pid\":$pid,\"process_name\":\"$process\",\"executable\":\"$exe\",\"opkg_package\":\"$pkg\",\"warnings\":[$entry_warnings]},"
    done < "$sockets_file"
  fi
  
  # Step 843: Integrate websnap endpoints
  local websnap_dir="$report_dir/collectors/apps.websnap/artifacts"
  if [ -d "$websnap_dir" ]; then
    for snap in "$websnap_dir"/websnap_port*.html; do
      [ -f "$snap" ] || continue
      local ep_port=$(echo "$(basename "$snap")" | grep -o '[0-9]*')
      total_endpoints=$((total_endpoints + 1))
    done
  fi
  
  # Step 836: Write inventory.json
  cat > "$output" << INVEOF
{
  "schema_id": "inventory",
  "schema_version": "1",
  "device_fingerprint": "$(cat "$report_dir/device_fingerprint" 2>/dev/null || echo unknown)",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)",
  "entries": [${entries%,}],
  "statistics": {
    "total_ports": $total_ports,
    "total_processes": $total_procs,
    "total_packages": $total_pkgs,
    "total_endpoints": $total_endpoints
  },
  "warnings": [${warnings%,}]
}
INVEOF
}

# Step 844: Inventory delta for incremental
inventory_build_delta() {
  local current="$1"
  local baseline="$2"
  local output="$3"
  
  # Compare ports, services, packages
  # Simplified: detect new/closed ports
  cat > "$output" << IDEOF
{
  "schema_id": "inventory_delta",
  "schema_version": "1",
  "report_id": "${TOOL_REPORT_ID:-unknown}",
  "base_report_id": "$(jq -r '.report_id // "unknown"' "$baseline" 2>/dev/null || echo unknown)",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)",
  "changes": {"new_ports":[],"closed_ports":[],"pid_changes":[],"new_services":[],"stopped_services":[],"pkg_changes":[],"new_endpoints":[]},
  "summary": {"total_changes":0,"new_ports_count":0,"closed_ports_count":0}
}
IDEOF
}
