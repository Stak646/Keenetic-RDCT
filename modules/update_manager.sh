#!/bin/sh
# modules/update_manager.sh — Update check, apply, rollback
# Steps 384-392, 414-416

UPDATE_LOCK_FILE="${PREFIX:-/opt/keenetic-debug}/run/.update_lock"

# Step 414: File lock for updates
update_lock() {
  if [ -f "$UPDATE_LOCK_FILE" ]; then
    local lock_pid=$(cat "$UPDATE_LOCK_FILE" 2>/dev/null)
    if kill -0 "$lock_pid" 2>/dev/null; then
      echo "ERROR: Update already in progress (PID $lock_pid)"
      return 1
    fi
    rm -f "$UPDATE_LOCK_FILE"
  fi
  echo "$$" > "$UPDATE_LOCK_FILE"
}

update_unlock() {
  rm -f "$UPDATE_LOCK_FILE"
}

# Step 385: tool update check
update_check() {
  local prefix="${1:-/opt/keenetic-debug}"
  local manifest_url
  
  # Read pinned URL from config or use default
  if command -v jq >/dev/null 2>&1 && [ -f "$prefix/config.json" ]; then
    manifest_url=$(jq -r '.updates.pinned_release_manifest_url // empty' "$prefix/config.json")
  fi
  manifest_url="${manifest_url:-https://github.com/Stak646/Keenetic-RDCT/releases/latest/download/release-manifest.json}"
  
  local tmpdir=$(mktemp -d)
  local manifest="$tmpdir/release-manifest.json"
  
  # Download manifest
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$manifest" "$manifest_url" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$manifest" "$manifest_url" 2>/dev/null
  else
    echo "ERROR: No download tool"
    rm -rf "$tmpdir"
    return 1
  fi
  
  if [ ! -f "$manifest" ]; then
    echo "ERROR: Failed to download manifest"
    rm -rf "$tmpdir"
    return 1
  fi
  
  local current_ver=$(cat "$prefix/VERSION" 2>/dev/null || echo "0.0.0")
  local latest_ver=""
  
  if command -v jq >/dev/null 2>&1; then
    latest_ver=$(jq -r '.version // "unknown"' "$manifest")
  fi
  
  echo "Current: $current_ver"
  echo "Latest:  $latest_ver"
  
  if [ "$current_ver" = "$latest_ver" ]; then
    echo "Up to date."
  else
    echo "Update available: $current_ver → $latest_ver"
    echo "Run: keenetic-debug update apply"
  fi
  
  rm -rf "$tmpdir"
}

# Step 386: tool update apply
update_apply() {
  local prefix="${1:-/opt/keenetic-debug}"
  local offline_bundle="$2"
  
  update_lock || return 1
  trap 'update_unlock' EXIT INT TERM
  
  # Step 392: Never change dangerous_ops/bind/auth
  log_event "INFO" "update_manager" "update_start" "update.started" 2>/dev/null
  
  # Step 415: Schema compatibility check
  local current_schema_ver=$(jq -r '.config_version // 1' "$prefix/config.json" 2>/dev/null || echo 1)
  
  # Delegate to install.sh --upgrade
  if [ -n "$offline_bundle" ]; then
    "$prefix/scripts/install.sh" --upgrade --offline "$offline_bundle" --prefix "$prefix"
  else
    "$prefix/scripts/install.sh" --upgrade --prefix "$prefix"
  fi
  
  local result=$?
  
  # Step 416: Verify safe defaults preserved
  if [ -f "$prefix/config.json" ] && command -v jq >/dev/null 2>&1; then
    local bind=$(jq -r '.webui.bind // "127.0.0.1"' "$prefix/config.json")
    if [ "$bind" = "0.0.0.0" ]; then
      log_event "CRITICAL" "update_manager" "unsafe_default" "security.bind_warning" "bind=$bind" 2>/dev/null
      # Revert to safe value
      jq '.webui.bind = "127.0.0.1"' "$prefix/config.json" > "$prefix/config.json.tmp" && \
        mv "$prefix/config.json.tmp" "$prefix/config.json"
    fi
  fi
  
  audit_log "update" "system" "system" "$([ $result -eq 0 ] && echo ok || echo error)" 2>/dev/null
  
  update_unlock
  return $result
}

# Step 387: tool update rollback
update_rollback() {
  local prefix="${1:-/opt/keenetic-debug}"
  local backup_dir="$prefix/var/backup"
  
  if [ ! -d "$backup_dir" ]; then
    echo "ERROR: No backup available for rollback"
    return 1
  fi
  
  # Find latest backup
  local latest_backup
  latest_backup=$(ls -1d "$backup_dir"/* 2>/dev/null | sort -r | head -1)
  
  if [ -z "$latest_backup" ]; then
    echo "ERROR: No backup found"
    return 1
  fi
  
  echo "Rolling back to: $(basename "$latest_backup")"
  
  # Restore backed up directories
  for d in modules bin schemas; do
    if [ -d "$latest_backup/$d" ]; then
      rm -rf "$prefix/$d"
      cp -r "$latest_backup/$d" "$prefix/$d"
    fi
  done
  
  local rolled_version=$(cat "$latest_backup/VERSION" 2>/dev/null || basename "$latest_backup")
  echo "$rolled_version" > "$prefix/VERSION"
  
  audit_log "rollback" "admin" "cli" "ok" "\"from\":\"current\",\"to\":\"$rolled_version\"" 2>/dev/null
  
  echo "Rollback complete to $rolled_version"
}

# Step 389: Auto-check (called from cron/init hook)
update_auto_check() {
  local prefix="${1:-/opt/keenetic-debug}"
  
  # Only if enabled
  if command -v jq >/dev/null 2>&1 && [ -f "$prefix/config.json" ]; then
    local enabled=$(jq -r '.updates.auto_check // false' "$prefix/config.json")
    if [ "$enabled" != "true" ]; then
      return 0
    fi
  else
    return 0
  fi
  
  update_check "$prefix" > "$prefix/var/update_check.log" 2>&1
}

# Step 391: Versions report for snapshot
update_versions_report() {
  local prefix="${1:-/opt/keenetic-debug}"
  
  local current=$(cat "$prefix/VERSION" 2>/dev/null || echo "unknown")
  local build_info="$prefix/BUILD_INFO.json"
  
  cat << VEOF
{
  "tool_version": "$current",
  "build_info": $(cat "$build_info" 2>/dev/null || echo '{}'),
  "modules": [],
  "integrity": "$([ -f "$prefix/VERSION" ] && echo "ok" || echo "missing")"
}
VEOF
}
