#!/bin/sh
# modules/lib/safe_read.sh — Safe file reading, globbing, HTTP fetch
# Steps 588-590, 643-646

safe_read_file() {
  local file="$1" max_kb="${2:-1024}" output="$3"
  [ ! -r "$file" ] && return 1
  local size_kb=$(( $(wc -c < "$file" 2>/dev/null || echo 0) / 1024 ))
  if [ "$size_kb" -gt "$max_kb" ] 2>/dev/null; then
    head -c $((max_kb * 1024)) "$file" > "$output"
    echo "--- TRUNCATED ---" >> "$output"
  else
    cp "$file" "$output"
  fi
}

safe_glob() {
  local root="$1" max_depth="${2:-10}" max_files="${3:-10000}"
  local count=0
  _sg_walk "$root" 0 "$max_depth" "$max_files"
}

_sg_walk() {
  local dir="$1" depth="$2" maxd="$3" maxf="$4"
  [ "$depth" -ge "$maxd" ] && return
  for e in "$dir"/*; do
    [ -e "$e" ] || continue
    count=$((count + 1))
    [ "$count" -ge "$maxf" ] && return
    [ -L "$e" ] && continue
    if [ -d "$e" ]; then _sg_walk "$e" $((depth+1)) "$maxd" "$maxf"
    else echo "$e"; fi
  done
}

safe_http_fetch() {
  local url="$1" output="$2" timeout_s="${3:-5}" max_size_kb="${4:-1024}"
  case "$url" in
    http://127.0.0.1*|http://localhost*|http://192.168.*|http://10.*) ;;
    *) return 1 ;;
  esac
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time "$timeout_s" --max-filesize $((max_size_kb * 1024)) --no-location -o "$output" "$url" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout="$timeout_s" -O "$output" "$url" 2>/dev/null
  else return 1; fi
}
