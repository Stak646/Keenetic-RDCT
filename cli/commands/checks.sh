#!/bin/sh
# cli/commands/checks.sh — Step 912
checks_dispatch() {
  local subcmd="${1:-show}"; shift 2>/dev/null || true
  . "${PREFIX:-/opt/keenetic-debug}/modules/checks_engine.sh" 2>/dev/null
  case "$subcmd" in
    show) checks_show ;;
    export) checks_show ;;
    *) echo "Usage: keenetic-debug checks {show|export}" ;;
  esac
}
