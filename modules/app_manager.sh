#!/bin/sh
# modules/app_manager.sh — Service discovery and management
# Steps 846-851

INITD_DIR="/opt/etc/init.d"

# Step 847: List services with status
app_list() {
  local json="${1:-false}"
  
  if [ ! -d "$INITD_DIR" ]; then
    echo "No init.d directory found"
    return 1
  fi
  
  for svc in "$INITD_DIR"/S*; do
    [ -f "$svc" ] || continue
    local name=$(basename "$svc")
    local enabled="true"
    local running="false"
    local pid=""
    
    # Check if running
    local status_out=$("$svc" status 2>/dev/null || echo "stopped")
    echo "$status_out" | grep -qi 'running\|started\|alive' && running="true"
    
    # Try to find PID
    pid=$(echo "$status_out" | grep -oP '\d+' | head -1 2>/dev/null || echo "")
    
    if [ "$json" = "true" ]; then
      echo "{\"name\":\"$name\",\"path\":\"$svc\",\"enabled\":$enabled,\"running\":$running,\"pid\":\"$pid\"}"
    else
      printf "%-20s running=%-5s pid=%-6s %s\n" "$name" "$running" "${pid:-?}" "$svc"
    fi
  done
}

# Step 848: Start/stop/restart (requires dangerous_ops)
app_control() {
  local action="$1"  # start|stop|restart
  local service_name="$2"
  local dangerous=$(config_get dangerous_ops 2>/dev/null || echo "false")
  
  if [ "$dangerous" != "true" ]; then
    echo "$(t 'security.dangerous_ops_required' 2>/dev/null || echo 'Requires dangerous_ops=true')"
    return 1
  fi
  
  local svc_path="$INITD_DIR/$service_name"
  if [ ! -f "$svc_path" ]; then
    svc_path=$(find "$INITD_DIR" -name "*$service_name*" -type f | head -1)
  fi
  
  if [ -z "$svc_path" ] || [ ! -f "$svc_path" ]; then
    echo "Service not found: $service_name"
    return 1
  fi
  
  log_event "INFO" "app_manager" "app_${action}" "app.session_started" \
    "\"service\":\"$service_name\",\"action\":\"$action\"" 2>/dev/null
  audit_log "app_${action}" "admin" "cli" "ok" "\"service\":\"$service_name\"" 2>/dev/null
  
  "$svc_path" "$action"
}

# Step 849: Backup service config
app_backup() {
  local service_name="$1"
  local backup_dir="${2:-/tmp/app_backup}"
  
  mkdir -p "$backup_dir/$service_name"
  
  # Find config files related to this service
  local sname=$(echo "$service_name" | sed 's/^S[0-9]*//')
  for cfg in "/opt/etc/${sname}" "/opt/etc/${sname}.conf" "/opt/etc/${sname}/"*; do
    [ -e "$cfg" ] && cp -r "$cfg" "$backup_dir/$service_name/" 2>/dev/null
  done
  
  # SHA256 of backed-up files
  find "$backup_dir/$service_name" -type f -exec sha256sum {} + > "$backup_dir/$service_name/checksums.sha256" 2>/dev/null
  
  audit_log "backup" "admin" "cli" "ok" "\"service\":\"$service_name\",\"backup_dir\":\"$backup_dir\"" 2>/dev/null
  echo "Backup: $backup_dir/$service_name"
}

# Step 850: Restore (requires dangerous_ops)
app_restore() {
  local service_name="$1"
  local backup_dir="$2"
  
  if [ "$(config_get dangerous_ops 2>/dev/null)" != "true" ]; then
    echo "Requires dangerous_ops=true"
    return 1
  fi
  
  if [ ! -d "$backup_dir/$service_name" ]; then
    echo "No backup found for $service_name"
    return 1
  fi
  
  # Verify checksums
  if [ -f "$backup_dir/$service_name/checksums.sha256" ]; then
    cd "$backup_dir/$service_name" && sha256sum -c checksums.sha256 >/dev/null 2>&1 || {
      echo "Checksum verification failed"
      return 1
    }
  fi
  
  audit_log "restore" "admin" "cli" "ok" "\"service\":\"$service_name\"" 2>/dev/null
  echo "Restore from $backup_dir/$service_name"
}

# Step 851: Determine app endpoints using inventory
app_endpoints() {
  local service_name="$1"
  local inventory="$2"
  
  if [ -f "$inventory" ] && command -v jq >/dev/null 2>&1; then
    jq -r --arg s "$service_name" '.entries[] | select(.process_name | contains($s)) | "  port=\(.port) proto=\(.proto) bind=\(.bind_addr)"' "$inventory" 2>/dev/null
  fi
}
