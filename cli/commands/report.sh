#!/bin/sh
# cli/commands/report.sh — Steps 878-879
report_dispatch() {
  local subcmd="${1:-list}"; shift 2>/dev/null || true
  local prefix="${PREFIX:-/opt/keenetic-debug}"
  case "$subcmd" in
    list)
      echo "Reports:"
      for d in "$prefix/reports"/*/; do
        [ -d "$d" ] || continue
        local rid=$(basename "$d")
        local size=$(du -sh "$d" 2>/dev/null | awk '{print $1}')
        echo "  $rid ($size)"
      done
      ;;
    delete)
      local rid="$1"
      [ -z "$rid" ] && echo "Usage: report delete <report_id>" && return 1
      if [ "$(config_get dangerous_ops 2>/dev/null)" != "true" ]; then
        echo "$(t 'security.dangerous_ops_required' 2>/dev/null || echo 'Requires dangerous_ops=true')"
        return 1
      fi
      rm -rf "$prefix/reports/$rid" "$prefix/reports/${rid}.tar.gz"
      audit_log "delete_report" "admin" "cli" "ok" "\"report_id\":\"$rid\"" 2>/dev/null
      echo "Deleted: $rid"
      ;;
    download)
      local rid="$1"
      local archive="$prefix/reports/${rid}.tar.gz"
      if [ -f "$archive" ]; then
        echo "Archive: $archive"
        echo "SHA256: $(sha256sum "$archive" 2>/dev/null | awk '{print $1}')"
      else
        echo "Archive not found for: $rid"
      fi
      ;;
    redaction)
      local rid="$1"
      local rr="$prefix/reports/$rid/redaction_report.json"
      [ -f "$rr" ] && cat "$rr" || echo "No redaction report for: $rid"
      ;;
    *) echo "Usage: keenetic-debug report {list|delete|download|redaction} [report_id]" ;;
  esac
}
