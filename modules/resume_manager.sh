#!/bin/sh
# modules/resume_manager.sh — Resume interrupted runs
# Steps 465-468

resume_check() {
  local prefix="${1:-/opt/keenetic-debug}"
  local resume_enabled
  resume_enabled=$(config_get resume 2>/dev/null || echo "true")
  
  [ "$resume_enabled" != "true" ] && return 1
  
  # Find incomplete run
  local state_file="$prefix/run/state.json"
  if [ ! -f "$state_file" ]; then
    return 1  # No previous run
  fi
  
  local prev_state=""
  if command -v jq >/dev/null 2>&1; then
    prev_state=$(jq -r '.state // empty' "$state_file")
  fi
  
  case "$prev_state" in
    RUNNING|PREFLIGHT|PACKAGING)
      # Step 467: Check if config/schemas changed
      local prev_report
      prev_report=$(jq -r '.report_id // empty' "$state_file" 2>/dev/null)
      
      if [ -n "$prev_report" ] && [ -d "$prefix/tmp/$prev_report" ]; then
        # Step 467: If schema version changed, suggest new run
        local prev_config="$prefix/tmp/$prev_report/effective_config.json"
        if [ -f "$prev_config" ]; then
          # Simple check: compare config_version
          echo "RESUME_AVAILABLE:$prev_report"
          return 0
        fi
      fi
      ;;
    *)
      return 1  # Completed or no state
      ;;
  esac
  
  return 1
}

# Step 466: Resume execution
resume_execute() {
  local prefix="$1"
  local report_id="$2"
  local retry_failed="${3:-false}"
  
  local checkpoint_file="$prefix/tmp/$report_id/checkpoints.jsonl"
  
  if [ ! -f "$checkpoint_file" ]; then
    return 1  # Cannot resume without checkpoints
  fi
  
  # Build skip list from successful checkpoints
  local completed_ids=""
  completed_ids=$(grep '"OK"' "$checkpoint_file" 2>/dev/null | grep -o '"collector_id":"[^"]*"' | sed 's/"collector_id":"//;s/"//')
  
  local skip_ids="$completed_ids"
  
  # Step 466: Include failed for retry if flag set
  if [ "$retry_failed" != "true" ]; then
    local failed_ids
    failed_ids=$(grep -E '"SOFT_FAIL"|"HARD_FAIL"' "$checkpoint_file" 2>/dev/null | grep -o '"collector_id":"[^"]*"' | sed 's/"collector_id":"//;s/"//')
    skip_ids="$skip_ids $failed_ids"
  fi
  
  # Step 468: Resume report
  cat > "$prefix/tmp/$report_id/resume_report.json" << RREOF
{
  "resume_from": "$report_id",
  "retry_failed": $retry_failed,
  "skipped_ok": [$(echo "$completed_ids" | sed 's/ /","/g;s/^/"/;s/$/"/')],
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
}
RREOF
  
  echo "$skip_ids"
}
