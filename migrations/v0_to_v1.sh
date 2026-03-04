#!/bin/sh
# Migration: v0 (no version) → v1
migrate_config() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    local tmp="${file}.tmp.$$"
    jq '. + {config_version: 1} + (if .governor then {} else {governor: {cpu_limit_pct: 70, ram_limit_pct: 80, min_disk_free_mb: 50}} end)' \
      "$file" > "$tmp" && mv "$tmp" "$file"
  fi
}
