#!/bin/sh
# modules/lib/json_writer.sh — Safe JSON generation without jq
# Step 620: Minimal JSON writer for collectors on minimal systems

json_escape() {
  echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' ' '
}

json_object_start() { echo "{"; }
json_object_end() { echo "}"; }
json_array_start() { echo "["; }
json_array_end() { echo "]"; }

json_kv_str() {
  local key="$1" val="$2" comma="${3:-,}"
  printf '"%s":"%s"%s' "$key" "$(json_escape "$val")" "$comma"
}

json_kv_num() {
  local key="$1" val="$2" comma="${3:-,}"
  printf '"%s":%s%s' "$key" "$val" "$comma"
}

json_kv_bool() {
  local key="$1" val="$2" comma="${3:-,}"
  printf '"%s":%s%s' "$key" "$val" "$comma"
}

json_kv_null() {
  local key="$1" comma="${2:-,}"
  printf '"%s":null%s' "$key" "$comma"
}
