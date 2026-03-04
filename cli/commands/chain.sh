#!/bin/sh
# cli/commands/chain.sh — Steps 914-915, 939
chain_dispatch() {
  local subcmd="${1:-show}"; shift 2>/dev/null || true
  . "${PREFIX:-/opt/keenetic-debug}/modules/delta_manager.sh" 2>/dev/null
  statedb_init "${PREFIX:-/opt/keenetic-debug}"
  case "$subcmd" in
    show) statedb_chain_view ;;
    rebase) statedb_rebase ;;
    compact) statedb_compact ;;
    reset) statedb_reset ;;
    *) echo "Usage: keenetic-debug chain {show|rebase|compact|reset}" ;;
  esac
}
