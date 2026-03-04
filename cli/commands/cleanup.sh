#!/bin/sh
# cli/commands/cleanup.sh — Step 548: safe cleanup
# Removes temp and incomplete run states, keeps completed reports

cleanup_safe() {
  local prefix="${PREFIX:-/opt/keenetic-debug}"
  
  echo "Safe cleanup..."
  
  # Remove temp directories
  if [ -d "$prefix/tmp" ]; then
    find "$prefix/tmp" -maxdepth 1 -type d -name '*-*-*' -exec rm -rf {} + 2>/dev/null
    echo "  Cleaned: $prefix/tmp"
  fi
  
  # Remove stale state
  rm -f "$prefix/run/state.json" "$prefix/run/lock" "$prefix/run/.lock"
  echo "  Cleaned: stale locks/state"
  
  # Keep: reports/, var/, config.json, logs/
  echo "  Preserved: reports, config, logs"
  echo "Done."
}
