#!/bin/sh
# cli/commands/webui.sh — WebUI management
# Step 430: token rotate

webui_token_rotate() {
  local prefix="${PREFIX:-/opt/keenetic-debug}"
  local token_file="$prefix/var/.auth_token"
  
  if [ ! -f "$token_file" ]; then
    echo "ERROR: Token file not found: $token_file"
    return 1
  fi
  
  # Backup old token
  cp "$token_file" "${token_file}.bak"
  
  # Generate new token
  local token
  if command -v openssl >/dev/null 2>&1; then
    token=$(openssl rand -hex 32)
  elif [ -f /dev/urandom ]; then
    token=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
  else
    token="$(date +%s%N | sha256sum 2>/dev/null | cut -c1-64)"
  fi
  
  echo "$token" > "$token_file"
  chmod 0600 "$token_file"
  
  echo "Token rotated. New token in: $token_file"
  echo "Restart WebUI for the change to take effect."
  
  audit_log "token_rotate" "admin" "cli" "ok" 2>/dev/null
}
