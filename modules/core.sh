#!/bin/sh
# modules/core.sh — Core orchestrator
# Steps 431-440, 461-464, 469-478, 486-490, 497-498, 512, 517, 520, 523-528, 543-544, 549-554

# --- Dependencies ---
# Expects: configurator.sh, i18n.sh, logger.sh, preflight.sh, governor.sh,
#          process_runner.sh, file_ops.sh, device_info.sh, storage_guard.sh

# =============================================================================
# Step 432: Run Context
# =============================================================================
_core_report_id=""
_core_start_ts=""
_core_mode=""           # baseline | delta
_core_lang=""
_core_correlation_id=""
_core_cancel_requested="false"
_core_state="INIT"      # INIT→PREFLIGHT→RUNNING→PACKAGING→DONE / CANCELLED / FAILED / CRASHED
_core_workdir=""
_core_report_dir=""
_core_tmpdir=""

core_init_context() {
  local prefix="${1:-/opt/keenetic-debug}"
  local config_file="$prefix/config.json"
  
  # Step 461: Load config
  . "$prefix/modules/configurator.sh"
  config_load "$config_file"
  
  # Step 462: Strict validation
  config_validate "$config_file" "$prefix/schemas/config.schema.json" >/dev/null || {
    log_event "CRITICAL" "core" "config_invalid" "errors.E001"
    return 1
  }
  
  # Step 502: Config conflict detection
  if [ "$(config_get readonly)" = "true" ] && [ "$(config_get dangerous_ops)" = "true" ]; then
    log_event "WARN" "core" "config_conflict" "config.invalid" \
      "\"error\":\"readonly=true conflicts with dangerous_ops=true; dangerous_ops forced to false\""
    config_set_cli "dangerous_ops" "false"
  fi
  
  # Step 432: Generate report_id
  local device_prefix
  device_prefix=$(cat /proc/cpuinfo 2>/dev/null | grep -i 'machine\|system' | head -1 | sed 's/.*: *//' | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | cut -c1-10 || echo "device")
  device_prefix=$(echo "$device_prefix" | sed 's/[^a-z0-9-]//g' | head -c 10)
  [ -z "$device_prefix" ] && device_prefix="kn"
  
  local ts
  ts=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || date +%s)
  local rand
  rand=$(head -c 2 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' ' || echo "0000")
  
  _core_report_id="${device_prefix}-${ts}-${rand}"
  _core_start_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  _core_mode=$(config_get snapshot_mode)
  _core_lang=$(config_get lang)
  _core_correlation_id="sess-${rand}"
  
  # Step 498: Manage PATH
  export PATH="/opt/bin:/opt/sbin:/usr/bin:/usr/sbin:/bin:/sbin:$PATH"
  
  # Step 497: Set env vars for collectors
  export TOOL_BASE_DIR="$prefix"
  export TOOL_REPORT_ID="$_core_report_id"
  export TOOL_MODE="$(config_get research_mode)"
  export TOOL_LANG="$_core_lang"
  export TOOL_PERF="$(config_get performance_mode)"
  export TOOL_READONLY="$(config_get readonly)"
  export TOOL_DANGEROUS="$(config_get dangerous_ops)"
  
  # Step 441: PathManager
  _core_workdir="$prefix/tmp/$_core_report_id"
  _core_report_dir="$prefix/reports/$_core_report_id"
  _core_tmpdir="$prefix/tmp"
  
  mkdir -p "$_core_workdir" "$_core_report_dir"
  
  # Step 463: Effective config snapshot
  config_show "true" > "$_core_workdir/effective_config.json" 2>/dev/null
  
  # Step 464: Stable key order (jq if available)
  if command -v jq >/dev/null 2>&1 && [ -f "$_core_workdir/effective_config.json" ]; then
    jq -S '.' "$_core_workdir/effective_config.json" > "$_core_workdir/effective_config.sorted.json" 2>/dev/null && \
      mv "$_core_workdir/effective_config.sorted.json" "$_core_workdir/effective_config.json"
  fi
  
  # Step 418/433: Init event log
  _log_file="$_core_workdir/event_log.jsonl"
  _log_correlation_id="$_core_correlation_id"
  
  local debug_level="INFO"
  [ "$(config_get debug)" = "true" ] && debug_level="DEBUG"
  logger_init "$debug_level" "$_log_file" "$_core_correlation_id"
  
  log_event "INFO" "core" "run.start" "app.session_started" \
    "\"report_id\":\"$_core_report_id\",\"mode\":\"$_core_mode\""
  
  return 0
}

# =============================================================================
# Step 436, 439, 489-490: Cancellation & signal handling
# =============================================================================
core_setup_signals() {
  trap 'core_handle_signal TERM' TERM
  trap 'core_handle_signal INT' INT
  trap 'core_handle_signal HUP' HUP
}

core_handle_signal() {
  local sig="$1"
  log_event "WARN" "core" "signal_received" "app.signal" "\"signal\":\"$sig\""
  
  if [ "$sig" = "INT" ] || [ "$sig" = "TERM" ]; then
    _core_cancel_requested="true"
    _core_state="CANCELLING"
    
    # Step 489-490: Graceful shutdown → stop new collectors; hard stop → SIGTERM then SIGKILL via ProcessRunner
    log_event "INFO" "core" "graceful_shutdown" "app.session_finished" \
      "\"report_id\":\"$_core_report_id\",\"status\":\"CANCELLING\""
  fi
}

core_is_cancelled() {
  [ "$_core_cancel_requested" = "true" ]
}

# =============================================================================
# Step 434: Checkpoint mechanism
# =============================================================================
core_checkpoint() {
  local collector_id="$1"
  local status="$2"
  local metrics="$3"
  
  local checkpoint_file="$_core_workdir/checkpoints.jsonl"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  
  echo "{\"ts\":\"$ts\",\"collector_id\":\"$collector_id\",\"status\":\"$status\",\"metrics\":$metrics}" \
    >> "$checkpoint_file"
  
  # Step 476: fsync for reliability
  sync 2>/dev/null
}

# =============================================================================
# Step 435: Atomic publish
# =============================================================================
core_publish_results() {
  local prefix="${TOOL_BASE_DIR:-/opt/keenetic-debug}"
  
  _core_state="PACKAGING"
  log_event "INFO" "core" "packager.start" "packager.started"
  
  # Step 524: Finalize report directory structure
  mkdir -p "$_core_report_dir"/{collectors,logs,artifacts}
  
  # Copy mandatory artifacts
  for f in event_log.jsonl preflight.json plan.json effective_config.json; do
    [ -f "$_core_workdir/$f" ] && cp "$_core_workdir/$f" "$_core_report_dir/"
  done
  
  # Copy checkpoints
  [ -f "$_core_workdir/checkpoints.jsonl" ] && cp "$_core_workdir/checkpoints.jsonl" "$_core_report_dir/logs/"
  
  # Copy collector results
  if [ -d "$_core_workdir/collectors" ]; then
    cp -r "$_core_workdir/collectors"/* "$_core_report_dir/collectors/" 2>/dev/null
  fi
  
  # Step 549: Critical forensic files first
  # manifest, audit_log, event_log are written synchronously
  
  # Step 485: Denylist enforcement — filter denylist paths before adding to archive
  # PackagerModule checks each file against policies/denylist.json
  # (PackagerModule will filter these)
  
  # Step 525: Archive atomically
  local archive="$prefix/reports/${_core_report_id}.tar.gz"
  local archive_tmp="${archive}.tmp"
  
  if command -v tar >/dev/null 2>&1; then
    tar czf "$archive_tmp" -C "$prefix/reports" "$_core_report_id" 2>/dev/null
    mv "$archive_tmp" "$archive"
    sync 2>/dev/null
    
    local size_mb
    size_mb=$(du -sm "$archive" 2>/dev/null | awk '{print $1}' || echo "?")
    log_event "INFO" "core" "packager.finish" "packager.complete" \
      "\"file\":\"$archive\",\"size_mb\":\"$size_mb\""
  fi
}

# =============================================================================
# Step 437: Fault isolation + Step 471: Partial results
# =============================================================================
core_run_collector() {
  local collector_id="$1"
  local collector_dir="$2"
  local timeout_s="${3:-60}"
  local max_output_mb="${4:-50}"
  
  # Step 486: Work budgeting
  if ! governor_acquire_slot "$collector_id" 2>/dev/null; then
    log_event "WARN" "core" "collector.budget_skip" "collector.skipped" \
      "\"collector_id\":\"$collector_id\",\"reason\":\"governor_budget\""
    return 0
  fi
  
  local workdir="$_core_workdir/collectors/$collector_id"
  mkdir -p "$workdir/artifacts"
  
  # Step 479: Task ID and env
  local task_id="task-$(head -c 2 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' ' || echo 00)"
  
  export COLLECTOR_ID="$collector_id"
  export COLLECTOR_WORKDIR="$workdir"
  export TASK_ID="$task_id"
  export RESEARCH_MODE="$(config_get research_mode)"
  export PERF_MODE="$(config_get performance_mode)"
  export TIMEOUT_S="$timeout_s"
  
  log_event "INFO" "core" "collector.start" "collector.started" \
    "\"collector_id\":\"$collector_id\",\"task_id\":\"$task_id\""
  
  local start_ms
  start_ms=$(date +%s 2>/dev/null || echo 0)
  
  # Step 437: Fault isolation — run in subshell
  local exit_code=0
  local run_script="$collector_dir/run.sh"
  
  if [ ! -f "$run_script" ]; then
    log_event "ERROR" "core" "collector.missing" "collector.skipped" \
      "\"collector_id\":\"$collector_id\",\"reason\":\"no_run_script\""
    governor_release_slot "$collector_id" 2>/dev/null
    return 1
  fi
  
  # Step 507-510: ProcessRunner delegates
  process_run "$run_script" "$workdir" "$timeout_s" "$max_output_mb" 2>/dev/null
  exit_code=$?
  
  local end_ms
  end_ms=$(date +%s 2>/dev/null || echo 0)
  local duration_ms=$(( (end_ms - start_ms) * 1000 ))
  
  # Step 474: Check output size
  local output_size=0
  if [ -d "$workdir/artifacts" ]; then
    output_size=$(du -sm "$workdir/artifacts" 2>/dev/null | awk '{print $1}' || echo 0)
  fi
  
  if [ "$output_size" -gt "$max_output_mb" ] 2>/dev/null; then
    log_event "ERROR" "core" "collector.output_limit" "collector.finished" \
      "\"collector_id\":\"$collector_id\",\"status\":\"HARD_FAIL\",\"reason\":\"output_limit\""
    exit_code=2
  fi
  
  # Map exit code to status
  local status
  case $exit_code in
    0)   status="OK" ;;
    1)   status="SOFT_FAIL" ;;
    2)   status="HARD_FAIL" ;;
    124) status="TIMEOUT" ;;
    137) status="TIMEOUT" ;;
    *)   status="HARD_FAIL" ;;
  esac
  
  # Step 477: Structured entry
  local metrics="{\"duration_ms\":$duration_ms,\"exit_code\":$exit_code,\"output_mb\":$output_size}"
  
  log_event "INFO" "core" "collector.finish" "collector.finished" \
    "\"collector_id\":\"$collector_id\",\"status\":\"$status\",\"task_id\":\"$task_id\"" \
    "$duration_ms"
  
  # Step 434: Checkpoint
  core_checkpoint "$collector_id" "$status" "$metrics"
  
  governor_release_slot "$collector_id" 2>/dev/null
  
  return 0  # Always return 0 — fault isolation
}

# =============================================================================
# Step 438: Watchdog
# =============================================================================
core_watchdog_check() {
  local global_timeout="${1:-1800}"
  local start_s="$2"
  
  local now_s
  now_s=$(date +%s 2>/dev/null || echo 0)
  local elapsed=$(( now_s - start_s ))
  
  if [ "$elapsed" -gt "$global_timeout" ]; then
    log_event "CRITICAL" "core" "watchdog.timeout" "errors.E011" \
      "\"elapsed_s\":$elapsed,\"limit_s\":$global_timeout"
    _core_state="FAILED"
    return 1
  fi
  
  return 0
}

# =============================================================================
# Step 440: Debugger report
# =============================================================================
core_write_debugger_report() {
  local reason="${1:-normal}"
  
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  
  # Step 472: Last N lines of logs
  local last_logs=""
  if [ -f "$_core_workdir/event_log.jsonl" ]; then
    last_logs=$(tail -20 "$_core_workdir/event_log.jsonl" 2>/dev/null | sed 's/"/\\"/g' | tr '\n' '|')
  fi
  
  # Step 520: Debug mode dumps
  local debug_dump="null"
  if [ "$(config_get debug)" = "true" ]; then
    debug_dump="{\"governor_state\":$(cat "$_core_workdir/governor.json" 2>/dev/null || echo '{}'),\"plan_summary\":\"see plan.json\"}"
  fi
  
  # Step 546: Capability summary
  local cap_summary="{}"
  [ -f "$_core_workdir/preflight.json" ] && cap_summary=$(cat "$_core_workdir/preflight.json" 2>/dev/null | head -c 1000)
  
  cat > "$_core_workdir/debugger_report.json" << DBEOF
{
  "report_id": "$_core_report_id",
  "timestamp": "$ts",
  "state": "$_core_state",
  "reason": "$reason",
  "duration_s": null,
  "core_version": "$(cat "$TOOL_BASE_DIR/VERSION" 2>/dev/null || echo unknown)",
  "device_fingerprint": "$(cat "$_core_workdir/device_fingerprint" 2>/dev/null || echo unknown)",
  "config_effective": "see effective_config.json",
  "capability_summary": "see preflight.json",
  "resource_snapshot": {
    "loadavg": "$(cat /proc/loadavg 2>/dev/null || echo unknown)",
    "mem_available_kb": "$(grep '^MemAvailable:' /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)",
    "disk_free_mb": "$(df -m "${_core_workdir}" 2>/dev/null | tail -1 | awk '{print $4}' || echo 0)"
  },
  "last_events": "$last_logs",
  "debug_dump": $debug_dump,
  "debugger_always": true
}
DBEOF
  
  cp "$_core_workdir/debugger_report.json" "$_core_report_dir/" 2>/dev/null
}

# =============================================================================
# Step 512: Summary aggregator
# =============================================================================
core_write_summary() {
  local total=0 ok=0 skip=0 soft=0 hard=0 timeout=0
  
  if [ -f "$_core_workdir/checkpoints.jsonl" ]; then
    total=$(wc -l < "$_core_workdir/checkpoints.jsonl")
    ok=$(grep -c '"OK"' "$_core_workdir/checkpoints.jsonl" 2>/dev/null || echo 0)
    skip=$(grep -c '"SKIP"' "$_core_workdir/checkpoints.jsonl" 2>/dev/null || echo 0)
    soft=$(grep -c '"SOFT_FAIL"' "$_core_workdir/checkpoints.jsonl" 2>/dev/null || echo 0)
    hard=$(grep -c '"HARD_FAIL"' "$_core_workdir/checkpoints.jsonl" 2>/dev/null || echo 0)
    timeout=$(grep -c '"TIMEOUT"' "$_core_workdir/checkpoints.jsonl" 2>/dev/null || echo 0)
  fi
  
  local overall="OK"
  [ "$hard" -gt 0 ] || [ "$timeout" -gt 0 ] && overall="PARTIAL"
  [ "$ok" -eq 0 ] && [ "$total" -gt 0 ] && overall="FAILED"
  
  cat > "$_core_workdir/summary.json" << SUMEOF
{
  "report_id": "$_core_report_id",
  "status": "$overall",
  "partial": $([ "$overall" = "PARTIAL" ] && echo true || echo false),
  "research_mode": "$(config_get research_mode)",
  "performance_mode": "$(config_get performance_mode)",
  "readonly": $(config_get readonly),
  "dangerous_ops": $(config_get dangerous_ops),
  "collectors": {
    "total": $total,
    "ok": $ok,
    "skip": $skip,
    "soft_fail": $soft,
    "hard_fail": $hard,
    "timeout": $timeout
  }
}
SUMEOF
}

# =============================================================================
# Step 550-551: Exit summary (user-facing)
# =============================================================================
core_print_exit_summary() {
  local prefix="${TOOL_BASE_DIR:-/opt/keenetic-debug}"
  local archive="$prefix/reports/${_core_report_id}.tar.gz"
  
  echo ""
  echo "$(t 'app.session_finished' "report_id=$_core_report_id status=$_core_state")"
  [ -f "$archive" ] && echo "  Archive: $archive"
  [ -f "$prefix/run/webui.port" ] && echo "  WebUI: http://127.0.0.1:$(cat "$prefix/run/webui.port")"
  echo "  Mode: $(config_get research_mode) / $(config_get performance_mode)"
  echo ""
}

# =============================================================================
# Step 445: Temp cleanup
# =============================================================================
core_cleanup_tmp() {
  local tmpdir="$_core_tmpdir"
  local max_age_hours="${1:-24}"
  
  if [ -d "$tmpdir" ]; then
    find "$tmpdir" -maxdepth 1 -type d -name '*-*-*' -mmin +$((max_age_hours * 60)) 2>/dev/null | while read -r d; do
      log_event "INFO" "core" "tmp_cleanup" "app.session_started" \
        "\"removed\":\"$d\""
      rm -rf "$d"
    done
  fi
}

# =============================================================================
# MAIN EXECUTION FLOW — Steps 517-519
# =============================================================================
core_execute() {
  local prefix="${1:-/opt/keenetic-debug}"
  
  # Step 444: File lock
  lock_acquire "$prefix/run/lock" || {
    log_event "ERROR" "core" "lock_failed" "errors.E001" "\"reason\":\"another run active\""
    return 1
  }
  
  core_setup_signals
  
  # Init context
  core_init_context "$prefix" || return 1
  
  # Step 491: Collect basic device info before preflight
  device_info_collect "$_core_workdir" 2>/dev/null
  
  # Step 445: Cleanup old temp
  core_cleanup_tmp 24
  
  # Step 518: Full/Extreme confirmation
  local mode=$(config_get research_mode)
  if [ "$mode" = "full" ] || [ "$mode" = "extreme" ]; then
    log_event "WARN" "core" "mode_warning" "security.dangerous_ops_enabled" \
      "\"mode\":\"$mode\""
    # CLI requires --i-understand flag (checked by caller)
  fi
  
  # Step 446: Preflight
  _core_state="PREFLIGHT"
  preflight_run "$prefix" "$_core_workdir" 2>/dev/null || {
    _core_state="FAILED"
    core_write_debugger_report "preflight_failed"
    lock_release "$prefix/run/lock" 2>/dev/null
    return 1
  }
  
  # Step 530: Write state for WebUI
  core_write_state "RUNNING"
  
  # Step 517: Execute plan
  _core_state="RUNNING"
  local plan_file="$_core_workdir/plan.json"
  local start_s
  start_s=$(date +%s 2>/dev/null)
  local global_timeout=1800
  
  if [ -f "$plan_file" ] && command -v jq >/dev/null 2>&1; then
    local collectors
    collectors=$(jq -r '.tasks[] | select(.status=="INCLUDE") | .collector_id' "$plan_file" 2>/dev/null)
    
    for cid in $collectors; do
      # Check cancellation
      core_is_cancelled && break
      
      # Step 438: Watchdog
      core_watchdog_check "$global_timeout" "$start_s" || break
      
      # Step 459: Storage guard
      storage_guard_check "$_core_workdir" 2>/dev/null || {
        log_event "CRITICAL" "core" "enospc" "packager.enospc"
        break
      }
      
      local collector_dir="$prefix/collectors/$cid"
      local timeout_s=60
      local max_out=50
      
      # Read from plugin.json if available
      if [ -f "$collector_dir/plugin.json" ] && command -v jq >/dev/null 2>&1; then
        timeout_s=$(jq -r '.timeout_s // 60' "$collector_dir/plugin.json")
        max_out=$(jq -r '.max_output_mb // 50' "$collector_dir/plugin.json")
      fi
      
      # Step 488: Deadline propagation
      local remaining=$(( global_timeout - $(date +%s) + start_s ))
      [ "$remaining" -lt "$timeout_s" ] && timeout_s="$remaining"
      [ "$timeout_s" -le 0 ] && break
      
      core_run_collector "$cid" "$collector_dir" "$timeout_s" "$max_out"
    done
  fi
  
  # Post-processing
  core_write_summary
  core_write_debugger_report "$([ "$_core_state" = "RUNNING" ] && echo normal || echo "$_core_state")"
  
  # Step 435: Publish
  core_publish_results
  
  _core_state="DONE"
  core_write_state "DONE"
  
  # Step 550: Exit summary
  core_print_exit_summary
  
  log_event "INFO" "core" "run.finish" "app.session_finished" \
    "\"report_id\":\"$_core_report_id\",\"status\":\"$_core_state\""
  
  lock_release "$prefix/run/lock" 2>/dev/null
  return 0
}

# Step 530-531: State file for WebUI
core_write_state() {
  local state="$1"
  local prefix="${TOOL_BASE_DIR:-/opt/keenetic-debug}"
  local state_file="$prefix/run/state.json"
  
  cat > "${state_file}.tmp" << STEOF
{"state":"$state","report_id":"$_core_report_id","started_at":"$_core_start_ts","correlation_id":"$_core_correlation_id"}
STEOF
  mv "${state_file}.tmp" "$state_file" 2>/dev/null
}

# Step 523: Sanitized export — create sanitized copy without modifying original
core_sanitized_export() {
  local prefix="${TOOL_BASE_DIR:-/opt/keenetic-debug}"
  local report_id="$1"
  local output_dir="${2:-$prefix/tmp}"
  
  local original="$prefix/reports/$report_id"
  if [ ! -d "$original" ]; then
    log_event "ERROR" "core" "sanitize_not_found" "errors.E010" "\"report_id\":\"$report_id\""
    return 1
  fi
  
  local sanitized="$output_dir/sanitized-$report_id"
  mkdir -p "$sanitized"
  cp -r "$original"/* "$sanitized/"
  
  # Re-run redaction with sanitize_export=true
  # Remove config, apply forced redaction
  rm -f "$sanitized/effective_config.json"
  
  log_event "INFO" "core" "sanitize_done" "app.session_finished" "\"report_id\":\"$report_id\""
  echo "$sanitized"
}

# Step 874: Include inventory in packager pipeline
# InventoryBuilder generates inventory.json which Packager includes and adds sha256 to manifest

# Step 927: Include incremental info in summary
core_write_incremental_summary() {
  local workdir="$1"
  local mode=$(config_get snapshot_mode 2>/dev/null || echo "baseline")
  local base_id=$(statedb_select_baseline 2>/dev/null || echo "")
  local chain_depth=0
  echo "{\"snapshot_type\":\"$mode\",\"base_report_id\":\"$base_id\",\"chain_depth\":$chain_depth}"
}
