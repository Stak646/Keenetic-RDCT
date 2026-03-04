#!/bin/sh
# cli/commands/inventory.sh — Steps 864, 870
inventory_show() {
  local prefix="${PREFIX:-/opt/keenetic-debug}"
  local latest=$(ls -1td "$prefix/reports"/*/ 2>/dev/null | head -1)
  [ -z "$latest" ] && echo "No reports found" && return 1
  local inv="$latest/inventory.json"
  [ -f "$inv" ] && cat "$inv" || echo "No inventory in latest report"
}
