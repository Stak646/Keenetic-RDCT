#!/bin/sh
# modules/lock_manager.sh — File-based locking
# Steps 533, 444, 414

lock_acquire() {
  local lockfile="$1"
  local timeout="${2:-5}"
  
  local waited=0
  while [ -f "$lockfile" ]; do
    local lock_pid=$(cat "$lockfile" 2>/dev/null)
    
    # Check if holder is alive
    if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
      # Stale lock
      rm -f "$lockfile"
      break
    fi
    
    waited=$((waited + 1))
    [ "$waited" -ge "$timeout" ] && return 1
    sleep 1
  done
  
  echo "$$" > "$lockfile"
  return 0
}

lock_release() {
  local lockfile="$1"
  rm -f "$lockfile"
}

# Step 528: Safe delete (role-checked)
lock_safe_delete() {
  local target="$1"
  local role="${2:-readonly}"
  
  if [ "$role" != "admin" ]; then
    log_event "WARN" "lock_manager" "delete_denied" "errors.E005" \
      "\"target\":\"$target\",\"role\":\"$role\"" 2>/dev/null
    return 1
  fi
  
  if [ -e "$target" ]; then
    rm -rf "$target"
    audit_log "delete_report" "$role" "cli" "ok" "\"target\":\"$target\"" 2>/dev/null
    return 0
  fi
  return 1
}
