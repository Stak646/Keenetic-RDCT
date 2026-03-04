#!/bin/sh
# modules/logger.sh — Structured logging (JSONL + human-readable)
# Step 134, 170

LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3
LOG_LEVEL_CRITICAL=4

_log_level=$LOG_LEVEL_INFO
_log_file=""
_log_correlation_id=""

logger_init() {
  local level="${1:-INFO}"
  local log_file="${2:-}"
  local correlation_id="${3:-}"
  
  case "$level" in
    DEBUG) _log_level=$LOG_LEVEL_DEBUG ;;
    INFO)  _log_level=$LOG_LEVEL_INFO ;;
    WARN)  _log_level=$LOG_LEVEL_WARN ;;
    ERROR) _log_level=$LOG_LEVEL_ERROR ;;
    CRITICAL) _log_level=$LOG_LEVEL_CRITICAL ;;
  esac
  
  _log_file="$log_file"
  _log_correlation_id="$correlation_id"
}

# log_event LEVEL MODULE EVENT_ID MESSAGE_KEY [params] [duration_ms]
log_event() {
  local level="$1"
  local module="$2"
  local event_id="$3"
  local message_key="$4"
  local params="${5:-}"
  local duration_ms="${6:-null}"
  
  local level_num
  case "$level" in
    DEBUG) level_num=$LOG_LEVEL_DEBUG ;;
    INFO)  level_num=$LOG_LEVEL_INFO ;;
    WARN)  level_num=$LOG_LEVEL_WARN ;;
    ERROR) level_num=$LOG_LEVEL_ERROR ;;
    CRITICAL) level_num=$LOG_LEVEL_CRITICAL ;;
    *) level_num=$LOG_LEVEL_INFO ;;
  esac
  
  # Skip if below threshold
  [ "$level_num" -lt "$_log_level" ] && return
  
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)
  
  # JSONL entry
  local jsonl_entry="{\"ts\":\"$ts\",\"level\":\"$level\",\"module\":\"$module\",\"event_id\":\"$event_id\",\"message_key\":\"$message_key\""
  [ -n "$params" ] && jsonl_entry="$jsonl_entry,\"params\":{$params}"
  [ -n "$_log_correlation_id" ] && jsonl_entry="$jsonl_entry,\"correlation_id\":\"$_log_correlation_id\""
  [ "$duration_ms" != "null" ] && jsonl_entry="$jsonl_entry,\"duration_ms\":$duration_ms"
  jsonl_entry="$jsonl_entry}"
  
  # Write to log file
  if [ -n "$_log_file" ]; then
    echo "$jsonl_entry" >> "$_log_file"
  fi
  
  # Human-readable to stderr
  local human_msg
  human_msg=$(t "$message_key" "$params" 2>/dev/null || echo "$message_key")
  echo "$ts [$level] $module: $human_msg" >&2
}

# Audit log (append-only, management actions)
audit_log() {
  local action="$1"
  local role="$2"
  local source="$3"
  local result="$4"
  local details="${5:-}"
  local report_id="${6:-}"
  
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%s)
  
  local entry="{\"ts\":\"$ts\",\"action\":\"$action\",\"role\":\"$role\",\"source\":\"$source\",\"result\":\"$result\""
  [ -n "$details" ] && entry="$entry,\"details\":{$details}"
  [ -n "$report_id" ] && entry="$entry,\"report_id\":\"$report_id\""
  entry="$entry}"
  
  local audit_file="${AUDIT_LOG:-var/audit.log}"
  echo "$entry" >> "$audit_file" 2>/dev/null
}
