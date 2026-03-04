#!/bin/sh
# modules/collector_runner.sh — Execute individual collectors with isolation
# Steps 568-578, 583-592, 616-617, 625-628, 643-650, 652-653, 663

# Step 568: Run collector with full framework
cr_run_collector() {
  local cid="$1"
  local collector_dir="$2"
  local workdir="$3"
  local timeout_s="${4:-60}"
  local max_output_mb="${5:-50}"
  
  local plugin="$collector_dir/plugin.json"
  
  # Step 569: Create standard workdir structure
  mkdir -p "$workdir/artifacts" "$workdir/logs"
  
  # Step 570: Create input.json
  cr_write_input "$workdir" "$cid" "$plugin"
  
  # Step 652: Check executable permissions
  local run_script="$collector_dir/run.sh"
  if [ -f "$run_script" ]; then
    local perms=$(stat -c '%a' "$run_script" 2>/dev/null || echo "?")
    case "$perms" in
      *7*) log_event "WARN" "runner" "world_writable" "security.readonly_active" \
        "\"file\":\"$run_script\",\"perms\":\"$perms\"" 2>/dev/null ;;
    esac
  fi
  
  # Step 653: Check for symlinks in collector dir
  local symlinks=$(find "$collector_dir" -type l 2>/dev/null | head -5)
  if [ -n "$symlinks" ]; then
    log_event "WARN" "runner" "symlinks_in_collector" "security.readonly_active" \
      "\"collector_id\":\"$cid\"" 2>/dev/null
  fi
  
  # Step 577-578: Apply ulimit and renice for heavy collectors
  cr_apply_limits "$cid" "$plugin"
  
  # Step 574: Run with timeout
  local start_ts=$(date +%s 2>/dev/null)
  local exit_code=0
  
  # Step 639: Sandbox mode
  if [ "${TOOL_SANDBOX:-0}" = "1" ]; then
    export SANDBOX_FIXTURES="${TOOL_BASE_DIR}/tests/fixtures/sandbox"
  fi
  
  # Step 643: Network restriction env
  export NET_ALLOW="localhost,127.0.0.1"
  export NET_TIMEOUT_S="${NET_TIMEOUT_S:-5}"
  
  # Execute
  process_run "$run_script" "$workdir" "$timeout_s" "$max_output_mb" 2>/dev/null
  exit_code=$?
  
  local end_ts=$(date +%s 2>/dev/null)
  local duration_ms=$(( (end_ts - start_ts) * 1000 ))
  
  # Step 572: Check artifact size limit
  local art_size_mb=0
  if [ -d "$workdir/artifacts" ]; then
    art_size_mb=$(du -sm "$workdir/artifacts" 2>/dev/null | awk '{print $1}' || echo 0)
  fi
  
  if [ "$art_size_mb" -gt "$max_output_mb" ] 2>/dev/null; then
    log_event "WARN" "runner" "output_limit_exceeded" "collector.finished" \
      "\"collector_id\":\"$cid\",\"size_mb\":$art_size_mb,\"limit_mb\":$max_output_mb" 2>/dev/null
    exit_code=2
  fi
  
  # Step 573: Truncate stdout/stderr
  cr_truncate_logs "$workdir"
  
  # Map exit code → status
  local status
  case $exit_code in
    0) status="OK" ;;
    1) status="SOFT_FAIL" ;;
    2) status="HARD_FAIL" ;;
    124|137) status="TIMEOUT" ;;
    *) status="HARD_FAIL" ;;
  esac
  
  # Step 571: Check result.json exists, create surrogate if not
  if [ ! -f "$workdir/result.json" ]; then
    cr_write_surrogate_result "$workdir" "$cid" "$status" "$exit_code" "$duration_ms"
  fi
  
  # Step 591: Inject metadata into result.json
  cr_inject_metadata "$workdir" "$cid" "$plugin" "$status" "$duration_ms" "$art_size_mb"
  
  # Step 628: Write artifact index
  cr_write_artifact_index "$workdir"
  
  # Step 626: Post-processing (redaction placeholder)
  # RedactionEngine will process artifacts/ before packaging
  
  return 0  # Always 0 — fault isolation
}

# Step 570: Write input.json for collector
cr_write_input() {
  local workdir="$1"
  local cid="$2"
  local plugin="$3"
  
  cat > "$workdir/input.json" << INEOF
{
  "collector_id": "$cid",
  "research_mode": "${TOOL_MODE:-medium}",
  "performance_mode": "${TOOL_PERF:-auto}",
  "lang": "${TOOL_LANG:-en}",
  "readonly": ${TOOL_READONLY:-true},
  "dangerous_ops": ${TOOL_DANGEROUS:-false},
  "sandbox": ${TOOL_SANDBOX:-0},
  "workdir": "$workdir",
  "artifacts_dir": "$workdir/artifacts",
  "base_dir": "${TOOL_BASE_DIR:-/opt/keenetic-debug}",
  "report_id": "${TOOL_REPORT_ID:-unknown}"
}
INEOF
}

# Step 571: Surrogate result.json
cr_write_surrogate_result() {
  local workdir="$1"
  local cid="$2"
  local status="$3"
  local exit_code="$4"
  local duration_ms="$5"
  
  cat > "$workdir/result.json" << SEOF
{
  "schema_id": "result",
  "schema_version": "1",
  "collector_id": "$cid",
  "status": "$status",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)",
  "finished_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)",
  "duration_ms": $duration_ms,
  "metrics": {"output_size_bytes": 0, "commands_run": 0, "commands_skipped": 0, "commands_failed": 1},
  "data": {},
  "artifacts": [],
  "errors": [{"code": "$([ $exit_code -eq 124 ] && echo 'TIMEOUT' || echo 'MISSING_RESULT')", "message": "Collector did not produce result.json"}],
  "fingerprint": null,
  "_surrogate": true
}
SEOF
}

# Step 573: Truncate large stdout/stderr
cr_truncate_logs() {
  local workdir="$1"
  local max_kb=512
  
  for f in "$workdir/stdout.log" "$workdir/stderr.log"; do
    [ ! -f "$f" ] && continue
    local size_kb=$(( $(wc -c < "$f" 2>/dev/null || echo 0) / 1024 ))
    if [ "$size_kb" -gt "$max_kb" ] 2>/dev/null; then
      # Keep first 256KB + last 256KB
      local bytes=$((max_kb * 512))
      head -c "$bytes" "$f" > "${f}.trunc"
      echo "" >> "${f}.trunc"
      echo "--- TRUNCATED ($size_kb KB → ${max_kb} KB) ---" >> "${f}.trunc"
      echo "" >> "${f}.trunc"
      tail -c "$bytes" "$f" >> "${f}.trunc"
      mv "${f}.trunc" "$f"
    fi
  done
}

# Step 577-578: Apply ulimit/renice
cr_apply_limits() {
  local cid="$1"
  local plugin="$2"
  
  local perf="${TOOL_PERF:-auto}"
  
  # Step 577: ulimit
  if command -v ulimit >/dev/null 2>&1; then
    case "$perf" in
      lite) ulimit -t 60 2>/dev/null; ulimit -v 65536 2>/dev/null ;;
      middle) ulimit -t 120 2>/dev/null ;;
      hard) ;; # No limits
    esac
  fi
  
  # Step 578: renice for heavy collectors
  if command -v jq >/dev/null 2>&1 && [ -f "$plugin" ]; then
    local cost_cpu=$(jq -r '.estimated_cost.cpu_pct // 0' "$plugin" 2>/dev/null)
    if [ "$cost_cpu" -gt 30 ] 2>/dev/null && [ "$perf" != "hard" ]; then
      renice -n 15 $$ >/dev/null 2>&1
    fi
  fi
}

# Step 591: Inject metadata
cr_inject_metadata() {
  local workdir="$1"
  local cid="$2"
  local plugin="$3"
  local status="$4"
  local duration_ms="$5"
  local art_size_mb="$6"
  
  # Only if jq available
  if ! command -v jq >/dev/null 2>&1; then return; fi
  [ ! -f "$workdir/result.json" ] && return
  
  local version=$(jq -r '.version // "unknown"' "$plugin" 2>/dev/null)
  local tmp="$workdir/result.json.tmp"
  
  jq --arg v "$version" --arg d "$duration_ms" --arg s "$art_size_mb" \
    '. + {_framework: {collector_version: $v, duration_ms: ($d|tonumber), output_mb: ($s|tonumber), tool_version: (env.TOOL_VERSION // "unknown")}}' \
    "$workdir/result.json" > "$tmp" 2>/dev/null && mv "$tmp" "$workdir/result.json"
}

# Step 628: Write artifact index
cr_write_artifact_index() {
  local workdir="$1"
  local index_file="$workdir/artifacts_index.json"
  
  echo '{"files":[' > "$index_file"
  local first=1
  
  find "$workdir/artifacts" -type f 2>/dev/null | while read -r f; do
    local rel=$(echo "$f" | sed "s|$workdir/||")
    local size=$(wc -c < "$f" 2>/dev/null || echo 0)
    local hash=""
    if command -v sha256sum >/dev/null 2>&1; then
      hash=$(sha256sum "$f" | awk '{print $1}')
    fi
    
    [ $first -eq 0 ] && echo ","
    echo "{\"path\":\"$rel\",\"size\":$size,\"sha256\":\"$hash\"}"
    first=0
  done >> "$index_file"
  
  echo ']}' >> "$index_file"
}

# Step 625: Exclude reasons
cr_write_exclude_reasons() {
  local workdir="$1"
  # Collector writes skipped_items to result.json.data
  # Framework ensures format consistency
  true
}

# Step 616: UTF-8 / binary handling
cr_ensure_utf8() {
  local file="$1"
  if command -v iconv >/dev/null 2>&1; then
    iconv -f UTF-8 -t UTF-8 "$file" >/dev/null 2>&1 || {
      # Binary file — base64 encode
      local tmp="${file}.b64"
      base64 "$file" > "$tmp" 2>/dev/null && mv "$tmp" "$file"
      echo "binary_base64" > "${file}.encoding"
    }
  fi
}

# Step 663: No secrets in filenames
cr_validate_filenames() {
  local dir="$1"
  find "$dir" -type f 2>/dev/null | while read -r f; do
    local name=$(basename "$f")
    case "$name" in
      *password*|*token*|*secret*|*key=*)
        log_event "WARN" "runner" "secret_in_filename" "security.sanitize_info" \
          "\"file\":\"$name\"" 2>/dev/null ;;
    esac
  done
}
