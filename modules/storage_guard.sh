#!/bin/sh
# modules/storage_guard.sh — Disk space monitoring
# Steps 494-495, 459, 527, 540

storage_guard_check() {
  local workdir="$1"
  local min_free
  min_free=$(config_get storage_min_free_mb 2>/dev/null || config_get governor_min_disk_free_mb 2>/dev/null || echo 50)
  
  if command -v df >/dev/null 2>&1; then
    local free_mb
    free_mb=$(df -m "$workdir" 2>/dev/null | tail -1 | awk '{print $4}')
    
    if [ "${free_mb:-0}" -lt "$min_free" ] 2>/dev/null; then
      return 1  # ENOSPC risk
    fi
  fi
  
  return 0
}

# Step 527: Retention policy
storage_retention_cleanup() {
  local reports_dir="$1"
  local max_snapshots
  max_snapshots=$(config_get retention_max_snapshots 2>/dev/null || echo 20)
  local max_days
  max_days=$(config_get retention_max_days 2>/dev/null || echo 90)
  
  if [ ! -d "$reports_dir" ]; then
    return
  fi
  
  # Count reports
  local count
  count=$(ls -1d "$reports_dir"/*/ 2>/dev/null | wc -l)
  
  # Remove oldest if over limit
  if [ "$count" -gt "$max_snapshots" ] 2>/dev/null; then
    local to_remove=$((count - max_snapshots))
    ls -1td "$reports_dir"/*/ 2>/dev/null | tail -n "$to_remove" | while read -r d; do
      local rid=$(basename "$d")
      # Never remove active run
      [ -f "$d/../run/state.json" ] && grep -q "\"$rid\"" "$d/../run/state.json" 2>/dev/null && continue
      log_event "INFO" "storage" "retention_cleanup" "app.session_started" \
        "\"removed\":\"$rid\"" 2>/dev/null
      rm -rf "$d"
      rm -f "${d%.*/}.tar.gz"
    done
  fi
}
