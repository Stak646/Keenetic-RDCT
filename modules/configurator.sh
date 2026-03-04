#!/bin/sh
# modules/configurator.sh — Configuration loader and manager
# Priority: CLI flags > env vars > config.json > built-in defaults
# Step 273: Load config with documented priority order

# --- Constants ---
CONFIG_VERSION=1
DEFAULT_CONFIG_PATH="/opt/keenetic-debug/config.json"
BACKUP_SUFFIX=".bak"

# --- Priority chain documentation ---
# 1. CLI flags (--mode, --perf, --lang, --debug, etc.)
# 2. Environment variables (KEENETIC_DEBUG_MODE, KEENETIC_DEBUG_LANG, etc.)
# 3. config.json (user file)
# 4. Built-in defaults (from schema)

# --- Built-in defaults ---
_cfg_research_mode="medium"
_cfg_performance_mode="auto"
_cfg_lang="en"
_cfg_debug="false"
_cfg_readonly="true"
_cfg_dangerous_ops="false"
_cfg_resume="true"
_cfg_snapshot_mode="baseline"
_cfg_usb_only="false"
_cfg_sandbox_mode="false"
_cfg_webui_enabled="true"
_cfg_webui_bind="127.0.0.1"
_cfg_webui_port=""
_cfg_webui_port_range_start="5000"
_cfg_webui_port_range_end="5099"
_cfg_governor_cpu_limit_pct="70"
_cfg_governor_ram_limit_pct="80"
_cfg_governor_min_disk_free_mb="50"
_cfg_governor_min_workers="1"
_cfg_governor_max_workers=""
_cfg_governor_backoff_strategy="linear"
_cfg_mirror_enabled="false"
_cfg_mirror_max_depth="10"
_cfg_mirror_max_files="10000"
_cfg_mirror_max_total_mb="500"
_cfg_mirror_follow_symlinks="false"
_cfg_archive_format="tar.gz"
_cfg_archive_compression_level="6"
_cfg_checks_enabled="true"
_cfg_checks_ruleset="default"
_cfg_checks_privacy_aware="true"
_cfg_privacy_preview_secrets="false"
_cfg_privacy_hash_ips="true"
_cfg_privacy_hash_macs="true"
_cfg_incremental_chain_max_depth="10"
_cfg_incremental_rebase_policy="count"
_cfg_incremental_rebase_n="10"
_cfg_incremental_rebase_size_mb="500"
_cfg_incremental_delta_packaging="stream"
_cfg_retention_max_snapshots="20"
_cfg_retention_max_days="90"
_cfg_crypto_enabled="false"
_cfg_updates_enabled="false"
_cfg_updates_channel="stable"
_cfg_webui_session_timeout_s="3600"
_cfg_webui_max_response_mb="100"
_cfg_webui_rate_limit_rps="60"
_cfg_adapters_ssh_enabled="false"
_cfg_adapters_dry_run="false"
_cfg_storage_min_free_mb="50"
_cfg_storage_write_amplification_guard="true"
_cfg_max_log_kb="1024"

# --- Source tracking ---
# For each field we track where value came from
# Values: "default", "config", "env", "cli"
_src_research_mode="default"
_src_performance_mode="default"
_src_lang="default"
_src_debug="default"

# --- Loader ---
config_load() {
  local config_file="${1:-$DEFAULT_CONFIG_PATH}"
  
  # Phase 1: Load config.json if exists
  if [ -f "$config_file" ]; then
    _config_load_json "$config_file"
  fi
  
  # Phase 2: Override with env vars
  _config_load_env
  
  # Phase 3: CLI flags override last (done by caller via config_set_cli)
}

_config_load_json() {
  local file="$1"
  # Requires jq or python3 json
  if command -v jq >/dev/null 2>&1; then
    _cfg_from_json_jq "$file"
  elif command -v python3 >/dev/null 2>&1; then
    _cfg_from_json_py "$file"
  else
    log_event "WARN" "configurator" "config.no_json_parser" \
      "Cannot parse config.json: no jq or python3"
  fi
}

_cfg_from_json_jq() {
  local file="$1"
  local val
  
  val=$(jq -r '.research_mode // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_research_mode="$val" && _src_research_mode="config"
  
  val=$(jq -r '.performance_mode // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_performance_mode="$val" && _src_performance_mode="config"
  
  val=$(jq -r '.lang // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_lang="$val" && _src_lang="config"
  
  val=$(jq -r '.debug // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_debug="$val" && _src_debug="config"
  
  val=$(jq -r '.readonly // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_readonly="$val"
  
  val=$(jq -r '.dangerous_ops // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_dangerous_ops="$val"
  
  val=$(jq -r '.webui.bind // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_webui_bind="$val"
  
  val=$(jq -r '.governor.cpu_limit_pct // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_governor_cpu_limit_pct="$val"
  
  val=$(jq -r '.governor.ram_limit_pct // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_governor_ram_limit_pct="$val"
  
  val=$(jq -r '.governor.backoff_strategy // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_governor_backoff_strategy="$val"
  
  val=$(jq -r '.usb_only // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_usb_only="$val"
  
  val=$(jq -r '.privacy.preview_secrets // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_privacy_preview_secrets="$val"
  
  val=$(jq -r '.privacy.hash_ips // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_privacy_hash_ips="$val"
  
  val=$(jq -r '.privacy.hash_macs // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_privacy_hash_macs="$val"
  
  val=$(jq -r '.incremental.rebase_policy // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_incremental_rebase_policy="$val"
  
  val=$(jq -r '.incremental.delta_packaging // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_incremental_delta_packaging="$val"
  
  val=$(jq -r '.crypto.enabled // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_crypto_enabled="$val"
  
  val=$(jq -r '.updates.enabled // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_updates_enabled="$val"
  
  val=$(jq -r '.adapters.ssh.enabled // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_adapters_ssh_enabled="$val"
  
  val=$(jq -r '.storage.min_free_mb // empty' "$file" 2>/dev/null)
  [ -n "$val" ] && _cfg_storage_min_free_mb="$val"
}

_cfg_from_json_py() {
  local file="$1"
  # Fallback python3 loader — minimal, same logic
  python3 -c "
import json, sys, os
with open('$file') as f:
    c = json.load(f)
def p(path, default=''):
    obj = c
    for k in path.split('.'):
        if isinstance(obj, dict) and k in obj:
            obj = obj[k]
        else:
            return default
    return str(obj) if obj is not None else default
# Output as shell assignments
pairs = [
    ('research_mode', p('research_mode')),
    ('performance_mode', p('performance_mode')),
    ('lang', p('lang')),
    ('debug', p('debug')),
    ('readonly', p('readonly')),
    ('dangerous_ops', p('dangerous_ops')),
    ('webui_bind', p('webui.bind')),
    ('usb_only', p('usb_only')),
]
for k, v in pairs:
    if v: print(f'_cfg_{k}=\"{v}\"')
" 2>/dev/null | while IFS= read -r line; do
    eval "$line"
  done
}

_config_load_env() {
  [ -n "$KEENETIC_DEBUG_MODE" ] && _cfg_research_mode="$KEENETIC_DEBUG_MODE" && _src_research_mode="env"
  [ -n "$KEENETIC_DEBUG_PERF" ] && _cfg_performance_mode="$KEENETIC_DEBUG_PERF" && _src_performance_mode="env"
  [ -n "$KEENETIC_DEBUG_LANG" ] && _cfg_lang="$KEENETIC_DEBUG_LANG" && _src_lang="env"
  [ -n "$KEENETIC_DEBUG_DEBUG" ] && _cfg_debug="$KEENETIC_DEBUG_DEBUG" && _src_debug="env"
  [ -n "$TOOL_LANG" ] && _cfg_lang="$TOOL_LANG" && _src_lang="env"
}

config_set_cli() {
  local key="$1" val="$2"
  case "$key" in
    research_mode|mode) _cfg_research_mode="$val"; _src_research_mode="cli" ;;
    performance_mode|perf) _cfg_performance_mode="$val"; _src_performance_mode="cli" ;;
    lang) _cfg_lang="$val"; _src_lang="cli" ;;
    debug) _cfg_debug="$val"; _src_debug="cli" ;;
    readonly) _cfg_readonly="$val" ;;
    dangerous_ops) _cfg_dangerous_ops="$val" ;;
    dry_run) _cfg_adapters_dry_run="$val" ;;
    *) return 1 ;;
  esac
}

config_get() {
  local key="$1"
  eval "echo \"\$_cfg_$key\""
}

config_get_source() {
  local key="$1"
  eval "echo \"\${_src_$key:-default}\""
}

# Step 274: config show — effective config with source annotations
config_show() {
  local redact="${1:-false}"
  local token_val
  
  if [ "$redact" = "true" ]; then
    token_val="***REDACTED***"
  else
    token_val="(see var/.auth_token)"
  fi
  
  cat << SHOW_EOF
{
  "_meta": {"generated":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","redacted":$redact},
  "research_mode": {"value":"$_cfg_research_mode","source":"$_src_research_mode"},
  "performance_mode": {"value":"$_cfg_performance_mode","source":"$_src_performance_mode"},
  "lang": {"value":"$_cfg_lang","source":"$_src_lang"},
  "debug": {"value":$_cfg_debug,"source":"$_src_debug"},
  "readonly": $_cfg_readonly,
  "dangerous_ops": $_cfg_dangerous_ops,
  "usb_only": $_cfg_usb_only,
  "webui": {"bind":"$_cfg_webui_bind","port":"$_cfg_webui_port","auth_token":"$token_val"},
  "governor": {"cpu_limit_pct":$_cfg_governor_cpu_limit_pct,"ram_limit_pct":$_cfg_governor_ram_limit_pct,"min_disk_free_mb":$_cfg_governor_min_disk_free_mb,"backoff_strategy":"$_cfg_governor_backoff_strategy"},
  "privacy": {"preview_secrets":$_cfg_privacy_preview_secrets,"hash_ips":$_cfg_privacy_hash_ips,"hash_macs":$_cfg_privacy_hash_macs},
  "incremental": {"rebase_policy":"$_cfg_incremental_rebase_policy","delta_packaging":"$_cfg_incremental_delta_packaging"},
  "storage": {"min_free_mb":$_cfg_storage_min_free_mb,"write_amplification_guard":$_cfg_storage_write_amplification_guard}
}
SHOW_EOF
}

# Step 275: config validate
config_validate() {
  local config_file="${1:-$DEFAULT_CONFIG_PATH}"
  local schema_file="${2:-$(dirname "$0")/../schemas/config.schema.json}"
  
  if [ ! -f "$config_file" ]; then
    echo "$(t 'config.file_not_found' "file=$config_file")"
    return 1
  fi
  
  if command -v python3 >/dev/null 2>&1 && python3 -c "import jsonschema" 2>/dev/null; then
    python3 -c "
import json, sys
from jsonschema import validate, ValidationError
with open('$config_file') as f: data = json.load(f)
with open('$schema_file') as f: schema = json.load(f)
try:
    validate(data, schema)
    print('OK: config is valid')
except ValidationError as e:
    print('FAIL: ' + e.message)
    sys.exit(1)
"
  else
    # Basic: check JSON syntax
    if command -v jq >/dev/null 2>&1; then
      jq . "$config_file" >/dev/null 2>&1 && echo "OK: valid JSON (schema check skipped)" || echo "FAIL: invalid JSON"
    else
      echo "WARN: no validator available"
    fi
  fi
}

# Step 276: config set with atomic write
config_set_file() {
  local config_file="${1:-$DEFAULT_CONFIG_PATH}"
  local path="$2"
  local value="$3"
  
  if [ ! -f "$config_file" ]; then
    echo "{}" > "$config_file"
  fi
  
  # Backup
  cp "$config_file" "${config_file}${BACKUP_SUFFIX}"
  
  # Atomic write: temp → validate → rename
  local tmp="${config_file}.tmp.$$"
  
  if command -v jq >/dev/null 2>&1; then
    jq --arg v "$value" ".$path = (\$v | try tonumber // try (if . == \"true\" then true elif . == \"false\" then false else . end) // .)" \
      "$config_file" > "$tmp" 2>/dev/null
    
    if [ $? -eq 0 ]; then
      # Validate after change
      config_validate "$tmp" >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        mv "$tmp" "$config_file"
        sync 2>/dev/null
        echo "OK: $path = $value"
      else
        rm -f "$tmp"
        echo "FAIL: validation failed after change; restored backup"
        mv "${config_file}${BACKUP_SUFFIX}" "$config_file"
        return 1
      fi
    else
      rm -f "$tmp"
      echo "FAIL: jq error"
      return 1
    fi
  else
    echo "FAIL: jq required for config set"
    return 1
  fi
}

# Step 277: Config migration
config_migrate() {
  local config_file="${1:-$DEFAULT_CONFIG_PATH}"
  
  if [ ! -f "$config_file" ]; then
    return 0
  fi
  
  local current_version
  if command -v jq >/dev/null 2>&1; then
    current_version=$(jq -r '.config_version // 0' "$config_file" 2>/dev/null)
  else
    current_version=0
  fi
  
  if [ "$current_version" -ge "$CONFIG_VERSION" ] 2>/dev/null; then
    return 0  # up to date
  fi
  
  # Backup before migration
  cp "$config_file" "${config_file}.pre-migrate.$(date +%Y%m%d%H%M%S)"
  
  # Apply migrations step by step
  local v=$current_version
  while [ "$v" -lt "$CONFIG_VERSION" ]; do
    local migration="migrations/v${v}_to_v$((v+1)).sh"
    if [ -f "$migration" ]; then
      . "$migration"
      migrate_config "$config_file"
    fi
    v=$((v + 1))
  done
  
  # Update version
  if command -v jq >/dev/null 2>&1; then
    local tmp="${config_file}.tmp.$$"
    jq ".config_version = $CONFIG_VERSION" "$config_file" > "$tmp" && mv "$tmp" "$config_file"
  fi
  
  echo "Migrated config from v${current_version} to v${CONFIG_VERSION}"
}

# Step 305: config show --redact
config_show_redacted() {
  config_show "true"
}

# Step 306: config export sanitized
config_export() {
  config_show "true"
}

# Step 308: Path normalization and traversal protection
config_normalize_path() {
  local path="$1"
  local base_dir="${2:-/opt/keenetic-debug}"
  
  # Reject null bytes
  case "$path" in
    *"$(printf '\000')"*) echo "REJECT: null byte"; return 1 ;;
  esac
  
  # Reject ../ traversal
  case "$path" in
    *../*|*/..*) echo "REJECT: path traversal"; return 1 ;;
  esac
  
  # Must be within base_dir (unless explicit exception)
  case "$path" in
    "$base_dir"/*|"auto") echo "$path" ;;
    /tmp/sandbox_*) echo "$path" ;;  # sandbox exception
    *) echo "REJECT: outside base_dir"; return 1 ;;
  esac
}
