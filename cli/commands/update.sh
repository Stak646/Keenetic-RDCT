#!/bin/sh
# cli/commands/update.sh — Update management
# Steps 385-387, 390

update_dispatch() {
  local subcmd="${1:-check}"
  shift 2>/dev/null || true
  local prefix="${PREFIX:-/opt/keenetic-debug}"
  
  . "$prefix/modules/update_manager.sh" 2>/dev/null || {
    echo "ERROR: UpdateManager not available"
    return 1
  }
  
  case "$subcmd" in
    check)
      update_check "$prefix"
      ;;
    apply)
      local offline=""
      [ "${1:-}" = "--offline" ] && offline="$2"
      update_apply "$prefix" "$offline"
      ;;
    rollback)
      update_rollback "$prefix"
      ;;
    *)
      echo "Usage: keenetic-debug update {check|apply|rollback}"
      echo "  check               Check for available updates"
      echo "  apply [--offline F]  Apply update"
      echo "  rollback             Rollback to previous version"
      ;;
  esac
}
