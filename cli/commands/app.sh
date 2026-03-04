#!/bin/sh
# cli/commands/app.sh — Steps 865
app_dispatch() {
  local subcmd="${1:-status}"; shift 2>/dev/null || true
  . "${PREFIX:-/opt/keenetic-debug}/modules/app_manager.sh" 2>/dev/null
  case "$subcmd" in
    status) app_list "${1:-false}" ;;
    start|stop|restart) app_control "$subcmd" "$1" ;;
    backup) app_backup "$1" ;;
    restore) app_restore "$1" "$2" ;;
    *) echo "Usage: keenetic-debug app {status|start|stop|restart|backup|restore} [name]" ;;
  esac
}
