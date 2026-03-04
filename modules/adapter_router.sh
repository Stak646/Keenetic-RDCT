#!/bin/sh
# modules/adapter_router.sh — Route queries to best adapter
# Steps 555-560

_adapter_cache=""

# Step 555: Select adapter by capability
adapter_select() {
  local query_type="$1"  # rci_show, rci_command, file_read, process_list
  
  # Priority: ndm → rcicli → http_rci → ssh → fallback
  local ndm_enabled=$(config_get adapters_ndm_enabled 2>/dev/null || echo "true")
  local rci_enabled=$(config_get adapters_rcicli_enabled 2>/dev/null || echo "true")
  local http_enabled=$(config_get adapters_http_rci_enabled 2>/dev/null || echo "false")
  local ssh_enabled=$(config_get adapters_ssh_enabled 2>/dev/null || echo "false")
  
  case "$query_type" in
    rci_*)
      [ "$ndm_enabled" = "true" ] && command -v ndmc >/dev/null 2>&1 && { echo "ndm"; return; }
      [ "$rci_enabled" = "true" ] && command -v rcicli >/dev/null 2>&1 && { echo "rcicli"; return; }
      [ "$http_enabled" = "true" ] && { echo "http_rci"; return; }
      echo "none"
      ;;
    *)
      echo "shell"
      ;;
  esac
}

# Step 556: Safe queries whitelist for readonly mode
adapter_is_safe_query() {
  local query="$1"
  local readonly_mode
  readonly_mode=$(config_get readonly 2>/dev/null || echo "true")
  
  [ "$readonly_mode" != "true" ] && return 0  # All queries allowed
  
  # Whitelist of safe RCI queries
  case "$query" in
    "show interface"*|"show ip"*|"show version"*|"show system"*|"show running-config"*)
      return 0 ;;
    "show log"*|"show schedule"*|"show ndns"*|"show crypto"*)
      return 0 ;;
    *)
      log_event "WARN" "adapter" "unsafe_query_blocked" "security.readonly_active" \
        "\"query\":\"$query\"" 2>/dev/null
      return 1 ;;
  esac
}

# Step 558: Cache adapter results
adapter_cached_query() {
  local adapter="$1"
  local query="$2"
  local cache_key
  cache_key=$(echo "$query" | sha256sum 2>/dev/null | cut -c1-16 || echo "$query")
  
  local cache_file="${_core_workdir:-/tmp}/adapter_cache_${cache_key}"
  
  if [ -f "$cache_file" ]; then
    cat "$cache_file"
    return 0
  fi
  
  # Execute and cache
  local result=""
  case "$adapter" in
    ndm)
      result=$(ndmc -c "$query" 2>/dev/null) ;;
    rcicli)
      result=$(echo "$query" | rcicli 2>/dev/null) ;;
    http_rci)
      local endpoint=$(config_get adapters_allowlist_endpoints 2>/dev/null | head -1)
      result=$(curl -fsS --max-time 5 "${endpoint}${query}" 2>/dev/null) ;;
    *)
      result="UNSUPPORTED_ADAPTER" ;;
  esac
  
  echo "$result" > "$cache_file"
  echo "$result"
}

# Step 557: Adapter diagnostics for preflight
adapter_diagnose() {
  local diag=""
  
  if ! command -v ndmc >/dev/null 2>&1; then
    diag="${diag}ndm: not available (ndmc not found). "
  fi
  
  if ! command -v rcicli >/dev/null 2>&1; then
    diag="${diag}rcicli: not available. "
  fi
  
  local http_enabled=$(config_get adapters_http_rci_enabled 2>/dev/null || echo "false")
  if [ "$http_enabled" = "true" ]; then
    local endpoint=$(config_get adapters_allowlist_endpoints 2>/dev/null | head -1)
    if ! curl -fsS --max-time 2 "${endpoint:-http://127.0.0.1:79/rci/}" >/dev/null 2>&1; then
      diag="${diag}http_rci: enabled but endpoint unreachable. "
    fi
  fi
  
  local ssh_enabled=$(config_get adapters_ssh_enabled 2>/dev/null || echo "false")
  [ "$ssh_enabled" = "false" ] && diag="${diag}ssh: disabled by default. "
  
  [ -z "$diag" ] && diag="All configured adapters available."
  echo "$diag"
}

# Step 560: When all RCI adapters unavailable, continue with file/Entware collectors
adapter_fallback_available() {
  # Even without RCI, tool continues with shell/file collectors and produces snapshot with warnings
  local selected=$(adapter_select "rci_show")
  if [ "$selected" = "none" ]; then
    log_event "WARN" "adapter" "all_rci_unavailable" "preflight.no_entware" \
      "\"message\":\"No RCI adapter available. Continuing with file-based collectors only.\"" 2>/dev/null
    return 1  # Signal: no RCI, but don't fail
  fi
  return 0
}
