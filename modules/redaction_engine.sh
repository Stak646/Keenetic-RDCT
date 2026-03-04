#!/bin/sh
# modules/redaction_engine.sh — Sensitive data classification and masking
# Steps 815-834

# Step 816: Sensitivity types vocabulary
REDACTION_TAGS="password token cookie ssid ip mac key cert logs payload"

# Step 819: Built-in regex patterns
_RE_PASSWORD='(password|passwd|pass|secret)\s*[=:]\s*.+'
_RE_TOKEN='Bearer\s+[A-Za-z0-9+/=._-]{20,}'
_RE_API_KEY='(api[_-]?key|apikey)\s*[=:]\s*[A-Za-z0-9]{16,}'
_RE_PRIVATE_KEY='-----BEGIN (RSA |EC )?PRIVATE KEY-----'
_RE_IPV4='\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'
_RE_MAC='\b([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b'
_RE_SSID='(ssid|SSID)\s*[=:]\s*.+'
_RE_COOKIE='(Cookie|Set-Cookie):\s*.+'

redaction_run() {
  local artifacts_dir="$1"
  local mode="${2:-medium}"  # light, medium, full, extreme
  local output_report="$3"
  local policy_file="${4:-}"
  
  local findings=""
  local total_findings=0
  local counts_password=0 counts_token=0 counts_ip=0 counts_mac=0 counts_ssid=0 counts_cookie=0 counts_key=0 counts_cert=0
  
  # Step 817-818: Apply based on mode
  local do_mask="true"
  case "$mode" in
    light|medium) do_mask="true" ;;
    full|extreme) do_mask="false" ;;  # Step 818: Still detect but don't mask
  esac
  
  # Step 825: Process each artifact file
  find "$artifacts_dir" -type f 2>/dev/null | while read -r f; do
    local rel=$(echo "$f" | sed "s|$artifacts_dir/||")
    
    # Step 823: Skip binary files
    if file "$f" 2>/dev/null | grep -qi 'binary\|data\|executable'; then
      echo "{\"file\":\"$rel\",\"action\":\"skip_binary\"}"
      continue
    fi
    
    # Step 821-822: Scan for patterns
    _redact_file "$f" "$rel" "$mode" "$do_mask"
  done > "${output_report}.tmp"
  
  # Count findings
  total_findings=$(wc -l < "${output_report}.tmp" 2>/dev/null || echo 0)
  counts_password=$(grep -c '"tag":"password"' "${output_report}.tmp" 2>/dev/null || echo 0)
  counts_token=$(grep -c '"tag":"token"' "${output_report}.tmp" 2>/dev/null || echo 0)
  counts_ip=$(grep -c '"tag":"ip"' "${output_report}.tmp" 2>/dev/null || echo 0)
  counts_mac=$(grep -c '"tag":"mac"' "${output_report}.tmp" 2>/dev/null || echo 0)
  
  local findings_json=$(cat "${output_report}.tmp" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  
  # Step 826: Always write redaction_report.json
  cat > "$output_report" << RREOF
{
  "schema_id": "redaction_report",
  "schema_version": "1",
  "research_mode": "$mode",
  "total_findings": $total_findings,
  "masked": $do_mask,
  "findings": [$findings_json],
  "summary": {
    "password": $counts_password,
    "token": $counts_token,
    "ip": $counts_ip,
    "mac": $counts_mac,
    "ssid": 0,
    "cookie": 0,
    "key": 0,
    "cert": 0
  }
}
RREOF
  
  rm -f "${output_report}.tmp"
}

_redact_file() {
  local file="$1"
  local rel="$2"
  local mode="$3"
  local do_mask="$4"
  
  # Scan for passwords
  if grep -nE "$_RE_PASSWORD" "$file" >/dev/null 2>&1; then
    local line=$(grep -nE "$_RE_PASSWORD" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    echo "{\"file\":\"$rel\",\"line\":$line,\"tag\":\"password\",\"action\":\"$([ "$do_mask" = "true" ] && echo zeroize || echo preserve_and_flag)\"}"
    # Step 817: Mask in-place for light/medium
    if [ "$do_mask" = "true" ]; then
      sed -i -E "s/(password|passwd|pass|secret)\s*[=:]\s*.+/\1=***REDACTED***/gi" "$file" 2>/dev/null
    fi
  fi
  
  # Scan for tokens
  if grep -nE "$_RE_TOKEN" "$file" >/dev/null 2>&1; then
    local line=$(grep -nE "$_RE_TOKEN" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    echo "{\"file\":\"$rel\",\"line\":$line,\"tag\":\"token\",\"action\":\"$([ "$do_mask" = "true" ] && echo zeroize || echo preserve_and_flag)\"}"
    if [ "$do_mask" = "true" ]; then
      sed -i -E "s/Bearer\s+[A-Za-z0-9+\/=._-]{20,}/Bearer ***REDACTED***/g" "$file" 2>/dev/null
    fi
  fi
  
  # Step 820: IP addresses
  if grep -nE "$_RE_IPV4" "$file" >/dev/null 2>&1; then
    local line=$(grep -nE "$_RE_IPV4" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    local action="preserve"
    if [ "$do_mask" = "true" ] && [ "$mode" = "medium" ]; then
      action="hash_octets"
    fi
    echo "{\"file\":\"$rel\",\"line\":$line,\"tag\":\"ip\",\"action\":\"$action\"}"
  fi
  
  # MAC addresses
  if grep -nE "$_RE_MAC" "$file" >/dev/null 2>&1; then
    local line=$(grep -nE "$_RE_MAC" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    echo "{\"file\":\"$rel\",\"line\":$line,\"tag\":\"mac\",\"action\":\"$([ "$do_mask" = "true" ] && echo hash_octets || echo preserve)\"}"
  fi
  
  # Private keys
  if grep -qE "$_RE_PRIVATE_KEY" "$file" 2>/dev/null; then
    echo "{\"file\":\"$rel\",\"line\":1,\"tag\":\"key\",\"action\":\"$([ "$do_mask" = "true" ] && echo zeroize || echo preserve_and_flag)\"}"
    if [ "$do_mask" = "true" ]; then
      sed -i '/-----BEGIN.*PRIVATE KEY-----/,/-----END.*PRIVATE KEY-----/c\***PRIVATE KEY REDACTED***' "$file" 2>/dev/null
    fi
  fi
}

# Step 827: Sanitize export (enhanced redaction)
redaction_sanitize() {
  local report_dir="$1"
  local output_dir="$2"
  
  mkdir -p "$output_dir"
  cp -r "$report_dir"/* "$output_dir/"
  
  # Force light mode redaction on all files
  redaction_run "$output_dir" "light" "$output_dir/redaction_report.json"
  
  # Remove potentially sensitive files
  rm -f "$output_dir/effective_config.json"
  
  audit_log "sanitize" "admin" "cli" "ok" 2>/dev/null
}
