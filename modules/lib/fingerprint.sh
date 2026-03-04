#!/bin/sh
# modules/lib/fingerprint.sh — File fingerprint (mtime+size+partial hash)
# Steps 622-623

file_fingerprint() {
  local file="$1"
  local strategy="${2:-hybrid}"  # mtime_size, content_hash, hybrid
  
  [ ! -f "$file" ] && echo "MISSING" && return 1
  
  local size=$(wc -c < "$file" 2>/dev/null || echo 0)
  local mtime=$(stat -c '%Y' "$file" 2>/dev/null || stat -f '%m' "$file" 2>/dev/null || echo 0)
  
  case "$strategy" in
    mtime_size)
      echo "${mtime}:${size}"
      ;;
    content_hash)
      compute_sha256 "$file"
      ;;
    hybrid)
      # mtime+size for quick check, hash first 4KB for confirmation
      local partial_hash
      partial_hash=$(head -c 4096 "$file" 2>/dev/null | sha256sum 2>/dev/null | awk '{print $1}' || echo "none")
      echo "${mtime}:${size}:${partial_hash}"
      ;;
  esac
}

# Step 623: Log cursor
log_cursor_read() {
  local log_file="$1"
  local cursor_file="$2"
  
  if [ ! -f "$cursor_file" ]; then
    echo "0"  # Start from beginning
    return
  fi
  
  local saved_inode=$(grep 'inode' "$cursor_file" 2>/dev/null | head -1 | awk '{print $2}')
  local saved_offset=$(grep 'offset' "$cursor_file" 2>/dev/null | head -1 | awk '{print $2}')
  local current_inode=$(stat -c '%i' "$log_file" 2>/dev/null || echo 0)
  
  if [ "$saved_inode" = "$current_inode" ] 2>/dev/null; then
    echo "$saved_offset"  # Same file, continue from offset
  else
    echo "0"  # Rotated
  fi
}

log_cursor_save() {
  local log_file="$1"
  local cursor_file="$2"
  local offset="$3"
  
  local inode=$(stat -c '%i' "$log_file" 2>/dev/null || echo 0)
  echo "inode $inode" > "$cursor_file"
  echo "offset $offset" >> "$cursor_file"
  echo "ts $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" >> "$cursor_file"
}

# Step 624: Tail with cursor
tail_with_cursor() {
  local log_file="$1"
  local cursor_file="$2"
  local max_kb="${3:-512}"
  local output_file="$4"
  
  local offset=$(log_cursor_read "$log_file" "$cursor_file")
  local file_size=$(wc -c < "$log_file" 2>/dev/null || echo 0)
  
  if [ "$offset" -ge "$file_size" ] 2>/dev/null; then
    # No new data
    touch "$output_file"
    return
  fi
  
  local max_bytes=$((max_kb * 1024))
  local bytes_to_read=$((file_size - offset))
  [ "$bytes_to_read" -gt "$max_bytes" ] && bytes_to_read=$max_bytes
  
  dd if="$log_file" bs=1 skip="$offset" count="$bytes_to_read" > "$output_file" 2>/dev/null
  
  # Save new cursor
  local new_offset=$((offset + bytes_to_read))
  log_cursor_save "$log_file" "$cursor_file" "$new_offset"
}
HEOF

# Step 588: Safe file read
cat > modules/lib/safe_read.sh << 'SREOF'
#!/bin/sh
# modules/lib/safe_read.sh — Safe file reading with size limits
# Step 588

safe_read_file() {
  local file="$1"
  local max_kb="${2:-1024}"
  local output="$3"
  
  [ ! -r "$file" ] && return 1
  
  local size_kb=$(( $(wc -c < "$file" 2>/dev/null || echo 0) / 1024 ))
  
  if [ "$size_kb" -gt "$max_kb" ] 2>/dev/null; then
    head -c $((max_kb * 1024)) "$file" > "$output"
    echo "--- TRUNCATED (${size_kb}KB > ${max_kb}KB limit) ---" >> "$output"
  else
    cp "$file" "$output"
  fi
}

# Step 589: Safe glob with denylist
safe_glob() {
  local root="$1"
  local max_depth="${2:-10}"
  local max_files="${3:-10000}"
  local denylist="${4:-}"
  local callback="$5"
  local count=0
  
  _sg_walk "$root" 0 "$max_depth" "$max_files" "$denylist" "$callback"
}

_sg_walk() {
  local dir="$1" depth="$2" maxd="$3" maxf="$4" deny="$5" cb="$6"
  [ "$depth" -ge "$maxd" ] && return
  [ "$count" -ge "$maxf" ] && return
  
  for e in "$dir"/*; do
    [ -e "$e" ] || continue
    count=$((count + 1))
    [ "$count" -ge "$maxf" ] && return
    [ -L "$e" ] && continue  # Skip symlinks
    
    # Denylist check
    if [ -n "$deny" ] && echo "$e" | grep -qf "$deny" 2>/dev/null; then
      continue
    fi
    
    if [ -d "$e" ]; then
      _sg_walk "$e" $((depth+1)) "$maxd" "$maxf" "$deny" "$cb"
    else
      [ -n "$cb" ] && "$cb" "$e"
    fi
  done
}

# Step 590: Safe HTTP fetch
safe_http_fetch() {
  local url="$1"
  local output="$2"
  local timeout_s="${3:-5}"
  local max_size_kb="${4:-1024}"
  
  # Step 643-646: Only localhost/LAN, allowlist, no external redirects
  case "$url" in
    http://127.0.0.1*|http://localhost*|http://192.168.*|http://10.*)
      ;;
    *)
      log_event "WARN" "safe_http" "external_blocked" "security.readonly_active" \
        "\"url\":\"$url\"" 2>/dev/null
      return 1
      ;;
  esac
  
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time "$timeout_s" --max-filesize $((max_size_kb * 1024)) \
      --no-location -o "$output" "$url" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout="$timeout_s" -O "$output" "$url" 2>/dev/null
  else
    return 1
  fi
  
  # Step 645: Content-type guard
  # For web snapshots, only keep text/html/css/js/images
  # (simplified: trust content, full impl checks headers)
}
SREOF

echo "lib/json_writer.sh: $(wc -l < modules/lib/json_writer.sh) lines"
echo "lib/hash.sh: $(wc -l < modules/lib/hash.sh) lines"
echo "lib/fingerprint.sh: $(wc -l < modules/lib/fingerprint.sh) lines"
echo "lib/safe_read.sh: $(wc -l < modules/lib/safe_read.sh) lines"
echo "✅ all framework libraries"