#!/bin/sh
# modules/process_runner.sh — Run external commands with limits
# Steps 507-511

# Step 507: Run with timeout and limits
process_run() {
  local script="$1"
  local workdir="$2"
  local timeout_s="${3:-60}"
  local max_output_mb="${4:-50}"
  
  local stdout_file="$workdir/stdout.log"
  local stderr_file="$workdir/stderr.log"
  local exit_code=0
  
  # Step 508: ulimit if available
  local ulimit_applied="false"
  if command -v ulimit >/dev/null 2>&1; then
    # Max file size (MB to blocks)
    ulimit -f $((max_output_mb * 1024)) 2>/dev/null && ulimit_applied="true"
  fi
  
  # Step 509: requires_root check
  # (done by caller in core.sh based on plugin.json)
  
  # Step 510: dangerous check
  # (done by caller in core.sh based on plugin.json)
  
  # Run with timeout
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_s" sh "$script" \
      > "$stdout_file" 2> "$stderr_file"
    exit_code=$?
  else
    # BusyBox timeout fallback
    sh "$script" > "$stdout_file" 2> "$stderr_file" &
    local pid=$!
    local waited=0
    while kill -0 "$pid" 2>/dev/null; do
      sleep 1
      waited=$((waited + 1))
      if [ "$waited" -ge "$timeout_s" ]; then
        kill -TERM "$pid" 2>/dev/null
        sleep 1
        kill -KILL "$pid" 2>/dev/null
        exit_code=124  # TIMEOUT
        break
      fi
    done
    if [ $exit_code -eq 0 ]; then
      wait "$pid" 2>/dev/null
      exit_code=$?
    fi
  fi
  
  # Step 511: Metrics
  local bytes_out=0 bytes_err=0
  [ -f "$stdout_file" ] && bytes_out=$(wc -c < "$stdout_file" 2>/dev/null || echo 0)
  [ -f "$stderr_file" ] && bytes_err=$(wc -c < "$stderr_file" 2>/dev/null || echo 0)
  
  # Truncate large outputs
  local max_bytes=$((max_output_mb * 1024 * 1024))
  if [ "$bytes_out" -gt "$max_bytes" ] 2>/dev/null; then
    head -c "$max_bytes" "$stdout_file" > "${stdout_file}.trunc"
    mv "${stdout_file}.trunc" "$stdout_file"
  fi
  
  return $exit_code
}

# Run a single command and capture output
process_run_cmd() {
  local cmd="$1"
  local output_file="$2"
  local timeout_s="${3:-30}"
  
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_s" sh -c "$cmd" > "$output_file" 2>&1
  else
    sh -c "$cmd" > "$output_file" 2>&1
  fi
  return $?
}
