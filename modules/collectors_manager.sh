#!/bin/sh
# modules/collectors_manager.sh — Collector registry, validation, scheduling
# Steps 562-567, 579-582, 599-601, 618, 640-642, 648, 651-660

COLLECTORS_DIR="${TOOL_BASE_DIR:-/opt/keenetic-debug}/collectors"
REGISTRY_FILE="$COLLECTORS_DIR/registry.json"

# Step 562: Scan and load collectors
cm_scan_collectors() {
  local collectors_dir="${1:-$COLLECTORS_DIR}"
  local result=""
  local count=0
  
  for cdir in "$collectors_dir"/*/; do
    [ -d "$cdir" ] || continue
    local cid=$(basename "$cdir")
    [ "$cid" = "_template" ] && continue
    
    local plugin="$cdir/plugin.json"
    if [ ! -f "$plugin" ]; then
      log_event "WARN" "collectors_manager" "plugin_missing" "collector.skipped" \
        "\"collector_id\":\"$cid\",\"reason\":\"no_plugin_json\"" 2>/dev/null
      continue
    fi
    
    # Step 564: Validate required fields
    if ! cm_validate_plugin "$plugin" "$cid"; then
      continue
    fi
    
    count=$((count + 1))
    result="${result}${cid},"
  done
  
  echo "${result%,}"
  return 0
}

# Step 564: Validate plugin.json
cm_validate_plugin() {
  local plugin="$1"
  local cid="$2"
  
  if command -v jq >/dev/null 2>&1; then
    local id=$(jq -r '.id // empty' "$plugin")
    local name=$(jq -r '.name // empty' "$plugin")
    local version=$(jq -r '.version // empty' "$plugin")
    local timeout=$(jq -r '.timeout_s // empty' "$plugin")
    local max_out=$(jq -r '.max_output_mb // empty' "$plugin")
    
    if [ -z "$id" ] || [ -z "$name" ] || [ -z "$version" ]; then
      log_event "WARN" "collectors_manager" "plugin_invalid" "collector.skipped" \
        "\"collector_id\":\"$cid\",\"reason\":\"missing_required_fields\"" 2>/dev/null
      return 1
    fi
    
    if [ -z "$timeout" ] || [ -z "$max_out" ]; then
      log_event "WARN" "collectors_manager" "plugin_incomplete" "collector.skipped" \
        "\"collector_id\":\"$cid\",\"reason\":\"missing_timeout_or_output_limit\"" 2>/dev/null
      return 1
    fi
  fi
  
  return 0
}

# Step 565: Calculate effective timeout/max_output with overrides
cm_effective_limits() {
  local cid="$1"
  local plugin="$2"
  local prefix="${TOOL_BASE_DIR:-/opt/keenetic-debug}"
  
  local base_timeout=60
  local base_maxout=50
  
  if command -v jq >/dev/null 2>&1; then
    base_timeout=$(jq -r '.timeout_s // 60' "$plugin")
    base_maxout=$(jq -r '.max_output_mb // 50' "$plugin")
    
    # Config overrides
    local cfg_timeout=$(jq -r --arg id "$cid" '.collectors[$id].timeout_s // empty' "$prefix/config.json" 2>/dev/null)
    local cfg_maxout=$(jq -r --arg id "$cid" '.collectors[$id].max_output_mb // empty' "$prefix/config.json" 2>/dev/null)
    
    [ -n "$cfg_timeout" ] && base_timeout="$cfg_timeout"
    [ -n "$cfg_maxout" ] && base_maxout="$cfg_maxout"
  fi
  
  # Clamp to limits (Step 268)
  [ "$base_timeout" -gt 300 ] 2>/dev/null && base_timeout=300
  [ "$base_timeout" -lt 5 ] 2>/dev/null && base_timeout=5
  [ "$base_maxout" -gt 200 ] 2>/dev/null && base_maxout=200
  [ "$base_maxout" -lt 1 ] 2>/dev/null && base_maxout=1
  
  echo "$base_timeout $base_maxout"
}

# Step 566-567: Check dependencies with fallbacks
cm_check_deps() {
  local plugin="$1"
  local workdir="$2"
  
  if ! command -v jq >/dev/null 2>&1; then
    return 0  # Can't check without jq
  fi
  
  local deps_ok="true"
  local fallback_used=""
  
  # Commands
  local req_cmds=$(jq -r '.dependencies.commands[]? // empty' "$plugin" 2>/dev/null)
  for cmd in $req_cmds; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      # Step 567: Try fallbacks
      local fallback=$(jq -r --arg c "$cmd" '.dependencies.optional_fallbacks[$c] // empty' "$plugin" 2>/dev/null)
      if [ -n "$fallback" ] && command -v "$fallback" >/dev/null 2>&1; then
        fallback_used="${fallback_used}${cmd}→${fallback},"
        # Step 662: Log fallback usage
        log_event "INFO" "collectors_manager" "dep_fallback" "collector.started" \
          "\"original\":\"$cmd\",\"fallback\":\"$fallback\"" 2>/dev/null
      else
        deps_ok="false"
        break
      fi
    fi
  done
  
  # Files
  local req_files=$(jq -r '.dependencies.files[]? // empty' "$plugin" 2>/dev/null)
  for f in $req_files; do
    if [ ! -r "$f" ]; then
      deps_ok="false"
      break
    fi
  done
  
  # Write fallback info to input.json
  if [ -n "$fallback_used" ] && [ -n "$workdir" ]; then
    echo "{\"fallbacks_used\":\"${fallback_used%,}\"}" > "$workdir/fallbacks.json" 2>/dev/null
  fi
  
  [ "$deps_ok" = "true" ]
}

# Step 600: Mode compatibility check
cm_mode_compatible() {
  local plugin="$1"
  local research_mode="${TOOL_MODE:-medium}"
  local perf_mode="${TOOL_PERF:-auto}"
  
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  
  # Check supported_research_modes
  local supported_rm=$(jq -r '.supported_research_modes[]? // empty' "$plugin" 2>/dev/null)
  if [ -n "$supported_rm" ]; then
    echo "$supported_rm" | grep -q "$research_mode" || return 1
  fi
  
  # Check supported_perf_modes
  local supported_pm=$(jq -r '.supported_perf_modes[]? // empty' "$plugin" 2>/dev/null)
  if [ -n "$supported_pm" ]; then
    echo "$supported_pm" | grep -q "$perf_mode" || return 1
  fi
  
  return 0
}

# Step 613: tool collectors list
cm_list_collectors() {
  local collectors_dir="${1:-$COLLECTORS_DIR}"
  
  echo "Available collectors:"
  echo ""
  
  for cdir in "$collectors_dir"/*/; do
    [ -d "$cdir" ] || continue
    local cid=$(basename "$cdir")
    [ "$cid" = "_template" ] && continue
    
    local plugin="$cdir/plugin.json"
    [ ! -f "$plugin" ] && continue
    
    if command -v jq >/dev/null 2>&1; then
      local name=$(jq -r '.name // "?"' "$plugin")
      local ver=$(jq -r '.version // "?"' "$plugin")
      local cat=$(jq -r '.category // "?"' "$plugin")
      local root=$(jq -r '.requires_root // false' "$plugin")
      local dangerous=$(jq -r '.dangerous // false' "$plugin")
      
      printf "  %-25s %-30s v%-8s cat=%-15s root=%s dangerous=%s\n" \
        "$cid" "$name" "$ver" "$cat" "$root" "$dangerous"
    else
      echo "  $cid"
    fi
  done
}

# Step 614: tool collectors describe <id>
cm_describe_collector() {
  local cid="$1"
  local collectors_dir="${2:-$COLLECTORS_DIR}"
  local plugin="$collectors_dir/$cid/plugin.json"
  
  if [ ! -f "$plugin" ]; then
    echo "Collector not found: $cid"
    return 1
  fi
  
  cat "$plugin"
}

# Step 615: tool collectors run <id> (debug)
cm_run_single() {
  local cid="$1"
  local collectors_dir="${2:-$COLLECTORS_DIR}"
  local output_dir="${3:-/tmp/collector_debug_$cid}"
  
  mkdir -p "$output_dir/artifacts" "$output_dir/logs"
  
  export COLLECTOR_ID="$cid"
  export COLLECTOR_WORKDIR="$output_dir"
  
  local run_script="$collectors_dir/$cid/run.sh"
  if [ ! -f "$run_script" ]; then
    echo "No run.sh for $cid"
    return 1
  fi
  
  echo "Running $cid in debug mode..."
  sh "$run_script"
  local rc=$?
  echo "Exit code: $rc"
  echo "Output: $output_dir"
  
  return $rc
}

# Step 641: --explain-plan
cm_explain_plan() {
  local plan_file="$1"
  
  if [ ! -f "$plan_file" ] || ! command -v jq >/dev/null 2>&1; then
    echo "No plan available"
    return
  fi
  
  echo "=== Plan Explanation ==="
  jq -r '.tasks[] | "  \(.collector_id): \(.status) — \(.reason)"' "$plan_file"
}

# Step 659: Topological sort by depends_on
cm_topo_sort() {
  local plan_file="$1"
  # Simple: already ordered by phase in preflight
  # Full topological sort would need cycle detection
  if command -v jq >/dev/null 2>&1 && [ -f "$plan_file" ]; then
    jq -r '.tasks | sort_by(.order) | .[].collector_id' "$plan_file"
  fi
}
