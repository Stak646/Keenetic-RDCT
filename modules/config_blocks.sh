#!/bin/sh
# modules/config_blocks.sh — Загрузка и валидация блоков конфигурации
# Зависит от: modules/configurator.sh, modules/i18n.sh
# Покрывает шаги: 279-288, 307-340

# ===== Step 279: Collectors block =====
config_load_collectors() {
  # Per-collector overrides: enable/disable, timeout_s, max_output_mb, parallel_group
  # Usage: config_collector_get <collector_id> <field> [default]
  true  # Loaded via config_get "collectors.<id>.<field>"
}

config_collector_get() {
  _cid="$1"; _field="$2"; _default="${3:-}"
  config_get "collectors.${_cid}.${_field}" "$_default"
}

config_collector_enabled() {
  _cid="$1"
  _val=$(config_collector_get "$_cid" "enabled" "true")
  [ "$_val" = "true" ]
}

# ===== Step 280: Mirror policy block =====
config_load_mirror() {
  MIRROR_ENABLED=$(config_get "mirror.enabled" "false")
  MIRROR_MAX_DEPTH=$(config_get "mirror.max_depth" "10")
  MIRROR_MAX_FILES=$(config_get "mirror.max_files" "10000")
  MIRROR_MAX_TOTAL_MB=$(config_get "mirror.max_total_mb" "500")
  MIRROR_MAX_FILE_MB=$(config_get "mirror.max_file_mb" "50")
  MIRROR_FOLLOW_SYMLINKS=$(config_get "mirror.follow_symlinks" "false")
}

# ===== Step 281: Privacy block =====
config_load_privacy() {
  PRIVACY_POLICY_FILE=$(config_get "privacy.policy_file" "policies/privacy.json")
  # Step 322: preview_secrets
  PRIVACY_PREVIEW_SECRETS=$(config_get "privacy.preview_secrets" "false")
  # Step 323: hash controls
  PRIVACY_HASH_IPS=$(config_get "privacy.hash_ips" "true")
  PRIVACY_HASH_MACS=$(config_get "privacy.hash_macs" "true")
  # Step 324: aggressive redaction paths
  PRIVACY_REDACT_PATHS=$(config_get "privacy.redact_paths" "")
  # Step 321: custom regex rules loaded via policy_loader
  PRIVACY_CUSTOM_RULES=$(config_get "privacy.custom_rules" "[]")
  # Step 316: sanitize export
  PRIVACY_SANITIZE_EXPORT=$(config_get "privacy.sanitize_export" "false")

  # Enforce: Light/Medium → preview_secrets must be false
  _mode=$(config_get "research_mode" "medium")
  case "$_mode" in
    light|medium)
      if [ "$PRIVACY_PREVIEW_SECRETS" = "true" ]; then
        log_event "WARN" "config" "preview_secrets_forced" "config.invalid" \
          "{\"error\":\"preview_secrets=true not allowed in $_mode mode\"}" 2>/dev/null || true
        PRIVACY_PREVIEW_SECRETS="false"
      fi
      ;;
  esac
}

# ===== Step 282: Checks block =====
config_load_checks() {
  CHECKS_ENABLED=$(config_get "checks.enabled" "true")
  CHECKS_RULESET=$(config_get "checks.ruleset" "default")
  CHECKS_PRIVACY_AWARE=$(config_get "checks.privacy_aware" "true")
  # Step 336: thresholds
  CHECKS_THRESH_NEW_PORTS=$(config_get "checks.thresholds.new_open_ports" "1")
  CHECKS_THRESH_CPU_SPIKE=$(config_get "checks.thresholds.cpu_spike_pct" "30")
  CHECKS_THRESH_RAM_SPIKE=$(config_get "checks.thresholds.ram_spike_pct" "30")
  CHECKS_THRESH_DISK_GROWTH=$(config_get "checks.thresholds.disk_growth_mb" "100")
  CHECKS_THRESH_CONNTRACK=$(config_get "checks.thresholds.conntrack_growth" "1000")
  # Step 337: emit_diffs
  CHECKS_EMIT_INVENTORY_DELTA=$(config_get "checks.emit_diffs.inventory_delta" "true")
  CHECKS_EMIT_CONFIG_DRIFT=$(config_get "checks.emit_diffs.config_drift" "true")
}

# ===== Step 283: Incremental block =====
config_load_incremental() {
  INCR_BASE_POLICY=$(config_get "incremental.base_policy" "last_baseline")
  INCR_BASE_REPORT_ID=$(config_get "incremental.base_report_id" "")
  INCR_CHAIN_MAX_DEPTH=$(config_get "incremental.chain_max_depth" "10")
  # Step 338: rebase policy
  INCR_REBASE_POLICY=$(config_get "incremental.rebase_policy" "every_n_deltas")
  INCR_REBASE_N=$(config_get "incremental.rebase_n" "10")
  INCR_REBASE_SIZE_MB=$(config_get "incremental.rebase_size_mb" "100")
  INCR_DIFF_DEFAULTS=$(config_get "incremental.diff_defaults" "hybrid")
  INCR_LOG_CURSOR_MODE=$(config_get "incremental.log_cursor_mode" "inode_offset")
  INCR_TOMBSTONES=$(config_get "incremental.tombstones_enabled" "true")
  # Step 339: delta packaging
  INCR_DELTA_PACKAGING=$(config_get "incremental.delta_packaging" "stream")
}

# ===== Step 284: WebUI block =====
config_load_webui() {
  WEBUI_ENABLED=$(config_get "webui.enabled" "true")
  WEBUI_BIND=$(config_get "webui.bind" "127.0.0.1")
  WEBUI_BIND_IFACE=$(config_get "webui.bind_iface" "")
  WEBUI_PORT=$(config_get "webui.port" "")
  WEBUI_PORT_RANGE_START=$(config_get "webui.port_range_start" "5000")
  WEBUI_PORT_RANGE_END=$(config_get "webui.port_range_end" "5099")
  WEBUI_HTTPS=$(config_get "webui.https" "false")
  # Step 331: session/idle timeout
  WEBUI_SESSION_TIMEOUT_S=$(config_get "webui.session_timeout_s" "3600")
  # Step 332: response size limits
  WEBUI_MAX_RESPONSE_MB=$(config_get "webui.max_response_mb" "100")
  WEBUI_MAX_DOWNLOAD_MB=$(config_get "webui.max_download_mb" "500")
  # Step 317: expose reports
  WEBUI_EXPOSE_REPORTS=$(config_get "webui.ui_expose_reports" "true")
  # Step 318: rate limits
  WEBUI_RPS=$(config_get "webui.rate_limits.rps" "60")
  WEBUI_BURST=$(config_get "webui.rate_limits.burst" "10")
  WEBUI_HEAVY_RPS=$(config_get "webui.rate_limits.heavy_rps" "5")
  # Step 333: LAN CIDR restriction
  WEBUI_ALLOWED_LAN_CIDRS=$(config_get "webui.allowed_lan_cidrs" "127.0.0.0/8,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12")

  # Safety check: reject 0.0.0.0
  if [ "$WEBUI_BIND" = "0.0.0.0" ]; then
    log_event "WARN" "config" "wan_bind_rejected" "security.bind_warning" \
      "{\"bind\":\"0.0.0.0\"}" 2>/dev/null || true
    WEBUI_BIND="127.0.0.1"
  fi
}

# ===== Step 285: Governor block =====
config_load_governor() {
  GOV_CPU_LIMIT=$(config_get "governor.cpu_limit_pct" "70")
  GOV_RAM_LIMIT=$(config_get "governor.ram_limit_pct" "80")
  GOV_MIN_DISK_FREE=$(config_get "governor.min_disk_free_mb" "50")
  # Step 327: min/max workers
  GOV_MIN_WORKERS=$(config_get "governor.min_workers" "1")
  GOV_MAX_WORKERS=$(config_get "governor.max_workers" "")
  GOV_IO_BUDGET=$(config_get "governor.io_budget_mb_s" "")
  GOV_SAMPLING_INTERVAL=$(config_get "governor.sampling_interval_s" "2")
  # Step 326: backoff strategy
  GOV_BACKOFF_STRATEGY=$(config_get "governor.backoff_strategy" "linear")
}

# ===== Step 286: Adapters block =====
config_load_adapters() {
  ADAPTER_NDM_ENABLED=$(config_get "adapters.ndm.enabled" "true")
  ADAPTER_RCICLI_ENABLED=$(config_get "adapters.rcicli.enabled" "true")
  # Step 334: http_rci with interface restriction
  ADAPTER_HTTP_RCI_ENABLED=$(config_get "adapters.http_rci.enabled" "false")
  ADAPTER_HTTP_RCI_BIND_IFACE=$(config_get "adapters.http_rci.bind_iface" "")
  ADAPTER_HTTP_RCI_ALLOWED_IFACES=$(config_get "adapters.http_rci.allowed_ifaces" "br0")
  # Step 335: SSH disabled by default
  ADAPTER_SSH_ENABLED=$(config_get "adapters.ssh.enabled" "false")
  # Step 311: dry_run
  ADAPTER_DRY_RUN=$(config_get "adapters.dry_run" "false")
  ADAPTER_ALLOW_ACTIVE=$(config_get "adapters.allow_active_checks" "false")
  # Step 312: allowlist endpoints
  ADAPTER_ALLOWLIST_ENDPOINTS=$(config_get "adapters.allowlist_endpoints" "/,/api,/status,/health")
}

# ===== Step 287: USB-only mode =====
config_enforce_usb_only() {
  _usb_only=$(config_get "usb_only" "false")
  if [ "$_usb_only" = "true" ]; then
    # Check if USB is mounted
    if ! mount | grep -q '/media/\|/mnt/.*usb\|/tmp/mnt/' 2>/dev/null; then
      echo "$(t 'preflight.warn_usb_required')"
      return 1
    fi
  fi
  return 0
}

# ===== Step 288: Retention policy =====
config_load_retention() {
  RETENTION_MAX_SNAPSHOTS=$(config_get "retention.max_snapshots" "20")
  RETENTION_MAX_DAYS=$(config_get "retention.max_days" "90")
  RETENTION_MAX_TOTAL_MB=$(config_get "retention.max_total_mb" "1000")
  RETENTION_AUTO_CLEANUP=$(config_get "retention.auto_cleanup" "false")
}

# ===== Step 307-308: Paths normalization =====
config_load_paths() {
  PATHS_BASE_DIR=$(config_get "paths.base_dir" "/opt/keenetic-debug")
  PATHS_WORKDIR=$(config_get "paths.workdir" "auto")
  PATHS_OUTPUT_DIR=$(config_get "paths.output_dir" "auto")
  PATHS_RUN_DIR=$(config_get "paths.run_dir" "run")
  PATHS_LOGS_DIR=$(config_get "paths.logs_dir" "var/logs")

  # Auto-resolve
  [ "$PATHS_WORKDIR" = "auto" ] && PATHS_WORKDIR="$PATHS_BASE_DIR/tmp"
  [ "$PATHS_OUTPUT_DIR" = "auto" ] && PATHS_OUTPUT_DIR="$PATHS_BASE_DIR/var/reports"

  # Path traversal protection (Step 308)
  for _p in "$PATHS_WORKDIR" "$PATHS_OUTPUT_DIR" "$PATHS_RUN_DIR" "$PATHS_LOGS_DIR"; do
    config_validate_path "$_p" || {
      log_event "ERROR" "config" "path_traversal" "config.invalid" \
        "{\"error\":\"path traversal in: $_p\"}" 2>/dev/null || true
      return 1
    }
  done
}

# ===== Step 309: Debug mode =====
config_apply_debug() {
  _debug=$(config_get "debug" "false")
  if [ "$_debug" = "true" ]; then
    LOG_LEVEL="DEBUG"
    GOVERNOR_DUMP_ENABLED="true"
  fi
}

# ===== Step 310: Readonly enforcement =====
config_enforce_readonly() {
  _readonly=$(config_get "readonly" "true")
  _dangerous=$(config_get "dangerous_ops" "false")
  if [ "$_readonly" = "true" ] && [ "$_dangerous" = "true" ]; then
    log_event "WARN" "config" "readonly_dangerous_conflict" "config.invalid" \
      "{\"error\":\"readonly=true but dangerous_ops=true; readonly wins\"}" 2>/dev/null || true
    # readonly takes precedence
  fi
}

# ===== Step 313: Max log size =====
config_get_max_log_kb() {
  config_get "storage.max_log_kb" "1024"
}

# ===== Step 314: Crypto block =====
config_load_crypto() {
  CRYPTO_ENABLED=$(config_get "crypto.enabled" "false")
  CRYPTO_METHOD=$(config_get "crypto.method" "")
  CRYPTO_ENCRYPT_SNAPSHOTS=$(config_get "crypto.encrypt_snapshots" "false")
  CRYPTO_SIGN_MANIFESTS=$(config_get "crypto.sign_manifests" "false")
}

# ===== Step 315, 340: Updates block =====
config_load_updates() {
  UPDATES_ENABLED=$(config_get "updates.enabled" "false")
  UPDATES_CHANNEL=$(config_get "updates.channel" "stable")
  UPDATES_AUTO_CHECK=$(config_get "updates.auto_check" "false")
  UPDATES_OFFLINE_BUNDLE=$(config_get "updates.offline_bundle_path" "")
  # Step 340: pinned manifest URL
  UPDATES_PINNED_MANIFEST_URL=$(config_get "updates.pinned_release_manifest_url" "")
}

# ===== Step 328-330: Storage block =====
config_load_storage() {
  STORAGE_USB_REQUIRED=$(config_get "storage.usb_mount_required" "false")
  STORAGE_USB_PREFERRED=$(config_get "storage.usb_preferred" "true")
  # Step 329: min free space
  STORAGE_MIN_FREE_MB=$(config_get "storage.min_free_mb" "50")
  # Step 330: write amplification guard
  STORAGE_WA_GUARD=$(config_get "storage.write_amplification_guard" "true")
}

# ===== Master loader: load all blocks =====
config_load_all() {
  config_load_paths || return 1
  config_load_webui
  config_load_governor
  config_load_collectors
  config_load_mirror
  config_load_privacy
  config_load_checks
  config_load_incremental
  config_load_adapters
  config_load_retention
  config_load_storage
  config_load_crypto
  config_load_updates
  config_apply_debug
  config_enforce_readonly
}
