#!/bin/sh
# modules/governor.sh — Resource management and throttling
# Steps 454-460, 486, 521-522

_gov_mode=""
_gov_max_workers=2
_gov_active_workers=0
_gov_cpu_limit=70
_gov_ram_limit=80
_gov_min_disk_mb=50
_gov_backoff="linear"
_gov_throttled="false"
_gov_metrics_file=""
_gov_peak_cpu=0
_gov_peak_ram=0
_gov_throttle_count=0

# Step 454: Init governor
governor_init() {
  _gov_mode=$(config_get performance_mode 2>/dev/null || echo "auto")
  _gov_cpu_limit=$(config_get governor_cpu_limit_pct 2>/dev/null || echo 70)
  _gov_ram_limit=$(config_get governor_ram_limit_pct 2>/dev/null || echo 80)
  _gov_min_disk_mb=$(config_get governor_min_disk_free_mb 2>/dev/null || echo 50)
  _gov_backoff=$(config_get governor_backoff_strategy 2>/dev/null || echo "linear")
  
  # Step 455: Mode-specific limits
  case "$_gov_mode" in
    lite)
      _gov_max_workers=1
      _gov_cpu_limit=30
      ;;
    middle)
      _gov_max_workers=2
      _gov_cpu_limit=50
      ;;
    hard)
      local cpus
      cpus=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)
      _gov_max_workers=$cpus
      _gov_cpu_limit=95
      ;;
    auto)
      local cpus
      cpus=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)
      _gov_max_workers=$cpus
      # Auto adjusts dynamically
      ;;
  esac
  
  # Override from config
  local cfg_max=$(config_get governor_max_workers 2>/dev/null)
  [ -n "$cfg_max" ] && [ "$cfg_max" != "null" ] && _gov_max_workers=$cfg_max
  
  local cfg_min=$(config_get governor_min_workers 2>/dev/null || echo 1)
  [ "$_gov_max_workers" -lt "$cfg_min" ] && _gov_max_workers=$cfg_min
  
  # Step 457: nice/ionice
  governor_apply_priority
}

# Step 457: Apply process priority
governor_apply_priority() {
  local nice_val=$(config_get governor_nice 2>/dev/null || echo 10)
  
  if command -v renice >/dev/null 2>&1; then
    renice -n "$nice_val" $$ >/dev/null 2>&1
  fi
  
  local ionice_class=$(config_get governor_ionice_class 2>/dev/null || echo "best-effort")
  if command -v ionice >/dev/null 2>&1; then
    case "$ionice_class" in
      idle) ionice -c 3 -p $$ 2>/dev/null ;;
      best-effort) ionice -c 2 -p $$ 2>/dev/null ;;
    esac
  fi
}

# Step 454: Read system metrics
governor_sample() {
  local loadavg=0
  local mem_pct=0
  local disk_free=0
  
  # Load average
  if [ -f /proc/loadavg ]; then
    loadavg=$(cat /proc/loadavg | awk '{print $1}')
  fi
  
  # Memory usage %
  if [ -f /proc/meminfo ]; then
    local total=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    local avail=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}' 2>/dev/null)
    [ -z "$avail" ] && avail=$(grep '^MemFree:' /proc/meminfo | awk '{print $2}')
    if [ "$total" -gt 0 ] 2>/dev/null; then
      mem_pct=$(( (total - avail) * 100 / total ))
    fi
  fi
  
  # Disk free MB
  if command -v df >/dev/null 2>&1 && [ -n "$_core_workdir" ]; then
    disk_free=$(df -m "$_core_workdir" 2>/dev/null | tail -1 | awk '{print $4}' || echo 0)
  fi
  
  # Track peaks
  [ "$mem_pct" -gt "$_gov_peak_ram" ] 2>/dev/null && _gov_peak_ram=$mem_pct
  
  # Step 455: Auto mode adaptation
  if [ "$_gov_mode" = "auto" ]; then
    # High load → reduce workers
    local load_int=$(echo "$loadavg" | cut -d. -f1)
    local cpus=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)
    
    if [ "$load_int" -gt "$((cpus * 2))" ] 2>/dev/null; then
      _gov_max_workers=1
      _gov_throttled="true"
      _gov_throttle_count=$((_gov_throttle_count + 1))
    elif [ "$load_int" -gt "$cpus" ] 2>/dev/null; then
      [ "$_gov_max_workers" -gt 1 ] && _gov_max_workers=$((_gov_max_workers - 1))
    fi
  fi
  
  # Step 458: OOM reaction
  if [ "$mem_pct" -gt "$_gov_ram_limit" ] 2>/dev/null; then
    _gov_max_workers=1
    _gov_throttled="true"
    _gov_throttle_count=$((_gov_throttle_count + 1))
    log_event "WARN" "governor" "governor.throttle" "governor.throttled" \
      "\"reason\":\"high_memory\",\"mem_pct\":$mem_pct" 2>/dev/null
  fi
  
  # Step 459: ENOSPC reaction
  if [ "${disk_free:-0}" -lt "$_gov_min_disk_mb" ] 2>/dev/null; then
    _gov_throttled="true"
    log_event "CRITICAL" "governor" "governor.enospc" "packager.enospc" \
      "\"disk_free_mb\":$disk_free" 2>/dev/null
  fi
}

# Step 456: Interface for planners
governor_acquire_slot() {
  local collector_id="$1"
  
  governor_sample
  
  if [ "$_gov_active_workers" -ge "$_gov_max_workers" ]; then
    return 1  # No slot available
  fi
  
  _gov_active_workers=$((_gov_active_workers + 1))
  return 0
}

governor_release_slot() {
  local collector_id="$1"
  [ "$_gov_active_workers" -gt 0 ] && _gov_active_workers=$((_gov_active_workers - 1))
}

governor_should_throttle() {
  governor_sample
  [ "$_gov_throttled" = "true" ]
}

governor_budget_remaining() {
  echo "workers_free=$((_gov_max_workers - _gov_active_workers)) cpu_limit=$_gov_cpu_limit"
}

# Step 460: Governor metrics for snapshot
governor_write_metrics() {
  local workdir="$1"
  
  cat > "$workdir/governor.json" << GEOF
{
  "mode": "$_gov_mode",
  "max_workers": $_gov_max_workers,
  "peak_cpu_pct": $_gov_peak_cpu,
  "peak_ram_pct": $_gov_peak_ram,
  "throttle_count": $_gov_throttle_count,
  "backoff_strategy": "$_gov_backoff",
  "final_state": "$([ "$_gov_throttled" = "true" ] && echo throttled || echo normal)"
}
GEOF
}

# Step 521-522: Profiler data
governor_write_profiler() {
  local workdir="$1"
  
  # Profiler data from checkpoints
  if [ -f "$workdir/checkpoints.jsonl" ]; then
    cp "$workdir/checkpoints.jsonl" "$workdir/profiler.json" 2>/dev/null
  fi
}
