#!/bin/sh
# modules/i18n.sh — Internationalization library
# Steps 291-296, 299-300

# --- Constants ---
I18N_DIR="${I18N_DIR:-$(dirname "$0")/../i18n}"
_i18n_lang="en"
_i18n_loaded="false"
_i18n_ru=""
_i18n_en=""

# --- Language selection (Step 294) ---
# Priority: 1) CLI --lang  2) config.lang  3) $TOOL_LANG  4) $LANG env  5) fallback "en"
i18n_init() {
  local cli_lang="$1"
  local config_lang="$2"
  
  if [ -n "$cli_lang" ]; then
    _i18n_lang="$cli_lang"
  elif [ -n "$config_lang" ]; then
    _i18n_lang="$config_lang"
  elif [ -n "$TOOL_LANG" ]; then
    _i18n_lang="$TOOL_LANG"
  elif [ -n "$LANG" ]; then
    case "$LANG" in
      ru*) _i18n_lang="ru" ;;
      *) _i18n_lang="en" ;;
    esac
  else
    _i18n_lang="en"
  fi
  
  # Validate
  case "$_i18n_lang" in
    ru|en) ;;
    *) _i18n_lang="en" ;;
  esac
  
  _i18n_load
}

_i18n_load() {
  local file="$I18N_DIR/${_i18n_lang}.json"
  local fallback="$I18N_DIR/en.json"
  
  if [ ! -f "$file" ]; then
    file="$fallback"
    _i18n_lang="en"
  fi
  
  _i18n_loaded="true"
}

# Step 293: t(key, params, lang) → string
# Usage: t "core.session_started" "report_id=kn3010-xxx"
# Params: key=value pairs separated by space or comma
t() {
  local key="$1"
  shift
  local params="$*"
  
  if [ "$_i18n_loaded" != "true" ]; then
    i18n_init
  fi
  
  local file="$I18N_DIR/${_i18n_lang}.json"
  local text=""
  
  # Extract value for key using jq or python3
  if command -v jq >/dev/null 2>&1; then
    text=$(jq -r --arg k "$key" '.[$k] // empty' "$file" 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    text=$(python3 -c "
import json
with open('$file') as f:
    d = json.load(f)
print(d.get('$key', ''))
" 2>/dev/null)
  fi
  
  # Step 295: Fallback to EN if key missing + warn
  if [ -z "$text" ] && [ "$_i18n_lang" != "en" ]; then
    local fallback="$I18N_DIR/en.json"
    if command -v jq >/dev/null 2>&1; then
      text=$(jq -r --arg k "$key" '.[$k] // empty' "$fallback" 2>/dev/null)
    fi
    if [ -n "$text" ]; then
      # Log missing key warning
      log_event "WARN" "i18n" "i18n.missing_key" "key=$key lang=$_i18n_lang fallback=en" 2>/dev/null
    fi
  fi
  
  # If still no text, return key itself
  if [ -z "$text" ]; then
    echo "[$key]"
    return
  fi
  
  # Substitute params: {param_name} → value
  local result="$text"
  for p in $params; do
    local pkey="${p%%=*}"
    local pval="${p#*=}"
    result=$(echo "$result" | sed "s/{${pkey}}/${pval}/g")
  done
  
  echo "$result"
}

# Step 297: severity/status → localized names
t_status() {
  local status="$1"
  case "$status" in
    OK) t "status.ok" ;;
    SKIP) t "status.skip" ;;
    SOFT_FAIL) t "status.soft_fail" ;;
    HARD_FAIL) t "status.hard_fail" ;;
    TIMEOUT) t "status.timeout" ;;
    *) echo "$status" ;;
  esac
}

t_severity() {
  local sev="$1"
  case "$sev" in
    INFO) t "severity.info" ;;
    WARN) t "severity.warn" ;;
    CRIT) t "severity.crit" ;;
    *) echo "$sev" ;;
  esac
}

# Step 296: Check language mixing guard
i18n_check_mixing() {
  local text="$1"
  local has_ru=$(echo "$text" | grep -c '[а-яА-ЯёЁ]')
  local has_en=$(echo "$text" | grep -c '[a-zA-Z]')
  # Allow mixing only for: paths, hashes, IDs, code blocks
  if [ "$has_ru" -gt 0 ] && [ "$has_en" -gt 0 ]; then
    echo "WARN: mixed languages detected"
    return 1
  fi
  return 0
}

i18n_get_lang() {
  echo "$_i18n_lang"
}
