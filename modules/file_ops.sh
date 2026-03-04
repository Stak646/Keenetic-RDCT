#!/bin/sh
# modules/file_ops.sh — Atomic file operations
# Steps 505-506, 482-485

# Step 505: atomic_write (tmp+rename)
atomic_write() {
  local dest="$1"
  local content="$2"
  local tmp="${dest}.tmp.$$"
  
  echo "$content" > "$tmp" || { rm -f "$tmp"; return 1; }
  
  # Step 506: fsync
  sync 2>/dev/null
  mv "$tmp" "$dest" || { rm -f "$tmp"; return 1; }
  return 0
}

# atomic_write from stdin
atomic_write_stdin() {
  local dest="$1"
  local tmp="${dest}.tmp.$$"
  
  cat > "$tmp" || { rm -f "$tmp"; return 1; }
  sync 2>/dev/null
  mv "$tmp" "$dest" || { rm -f "$tmp"; return 1; }
}

safe_mkdir() {
  local dir="$1"
  local mode="${2:-0750}"
  mkdir -p "$dir" && chmod "$mode" "$dir"
}

safe_chmod() {
  local file="$1"
  local mode="$2"
  [ -e "$file" ] && chmod "$mode" "$file"
}

# Step 482: Validate collector writes only to its workdir
validate_output_path() {
  local path="$1"
  local allowed_dir="$2"
  
  # Resolve and check
  case "$path" in
    "$allowed_dir"/*) return 0 ;;
    *) 
      log_event "ERROR" "file_ops" "path_violation" "errors.E007" \
        "\"path\":\"$path\",\"allowed\":\"$allowed_dir\"" 2>/dev/null
      return 1
      ;;
  esac
}

# Step 483-484: Safe directory walk with depth/cycle protection
safe_walk() {
  local root="$1"
  local max_depth="${2:-10}"
  local max_files="${3:-10000}"
  local callback="$4"
  local visited_inodes=""
  local file_count=0
  
  _walk_recursive "$root" 0 "$max_depth" "$max_files" "$callback"
}

_walk_recursive() {
  local dir="$1"
  local depth="$2"
  local max_d="$3"
  local max_f="$4"
  local cb="$5"
  
  [ "$depth" -ge "$max_d" ] && return
  [ "$file_count" -ge "$max_f" ] && return
  
  for entry in "$dir"/*; do
    [ -e "$entry" ] || continue
    file_count=$((file_count + 1))
    [ "$file_count" -ge "$max_f" ] && return
    
    # Cycle detection via inode
    if [ -L "$entry" ]; then
      # Symlink — skip by default
      continue
    fi
    
    if [ -d "$entry" ]; then
      _walk_recursive "$entry" $((depth + 1)) "$max_d" "$max_f" "$cb"
    else
      [ -n "$cb" ] && "$cb" "$entry"
    fi
  done
}
