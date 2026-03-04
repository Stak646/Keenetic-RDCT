#!/bin/sh
# modules/policy_loader.sh — Load and merge policies (denylist, privacy)
# Step 290: priority: user overrides > config inline > default files

_policy_denylist_rules=""
_policy_privacy_modes=""

policy_load() {
  local config_dir="${1:-/opt/keenetic-debug}"
  
  # Load denylist
  local denylist_file
  denylist_file=$(config_get "mirror_denylist_file" 2>/dev/null || echo "policies/denylist.json")
  
  # Merge: default + user
  local default_denylist="$config_dir/policies/denylist.default.json"
  local user_denylist="$config_dir/$denylist_file"
  
  if [ -f "$user_denylist" ]; then
    _policy_denylist_rules="$user_denylist"
  elif [ -f "$default_denylist" ]; then
    _policy_denylist_rules="$default_denylist"
  fi
  
  # Load privacy
  local privacy_file
  privacy_file=$(config_get "privacy_policy_file" 2>/dev/null || echo "policies/privacy.json")
  
  local default_privacy="$config_dir/policies/privacy.default.json"
  local user_privacy="$config_dir/$privacy_file"
  
  if [ -f "$user_privacy" ]; then
    _policy_privacy_modes="$user_privacy"
  elif [ -f "$default_privacy" ]; then
    _policy_privacy_modes="$default_privacy"
  fi
}

# Step 320: Version-aware merge (user additions preserved on update)
policy_merge_denylist() {
  local default_file="$1"
  local user_file="$2"
  local output_file="$3"
  
  if ! command -v jq >/dev/null 2>&1; then
    # No jq — just use user file as-is
    cp "$user_file" "$output_file"
    return
  fi
  
  # Merge: keep all user rules, add new default rules not in user
  jq -s '
    .[0] as $default | .[1] as $user |
    {
      version: ($user.version // $default.version),
      description: ($user.description // $default.description),
      rules: (
        ($user.rules // []) + 
        [($default.rules // [])[] | 
          select(.pattern as $p | ($user.rules // []) | map(.pattern) | index($p) | not)]
      )
    }
  ' "$default_file" "$user_file" > "$output_file"
}

policy_check_denylist() {
  local path="$1"
  local denylist_file="$_policy_denylist_rules"
  
  if [ -z "$denylist_file" ] || [ ! -f "$denylist_file" ]; then
    return 1  # not denied
  fi
  
  # Quick glob check (simplified — full impl uses jq or shell glob)
  if command -v jq >/dev/null 2>&1; then
    jq -r '.rules[].pattern' "$denylist_file" 2>/dev/null | while read -r pattern; do
      case "$path" in
        $pattern) echo "DENY: $pattern"; return 0 ;;
      esac
    done
  fi
  
  return 1
}

policy_get_redaction_action() {
  local tag="$1"  # password, token, ip, mac, etc.
  local mode="$2"  # light, medium, full, extreme
  local privacy_file="$_policy_privacy_modes"
  
  if [ -z "$privacy_file" ] || [ ! -f "$privacy_file" ]; then
    echo "zeroize"  # safe default
    return
  fi
  
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg m "$mode" --arg t "$tag" '.modes[$m][$t] // "zeroize"' "$privacy_file" 2>/dev/null
  else
    echo "zeroize"
  fi
}
