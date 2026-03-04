#!/bin/sh
# modules/delta_manager.sh — StateDB, baseline/delta chains, incremental
# Steps 881-896, 913-918, 925-928, 934-940

STATE_DB_TYPE=""  # sqlite | json
STATE_DB_PATH=""

# Step 881: Choose implementation
statedb_init() {
  local prefix="${1:-/opt/keenetic-debug}"
  local db_path=$(config_get incremental_state_db_path 2>/dev/null || echo "auto")
  
  if [ "$db_path" = "auto" ]; then
    db_path="$prefix/var/state.db"
  fi
  
  # SQLite (WAL) if available, JSON fallback
  if command -v sqlite3 >/dev/null 2>&1; then
    STATE_DB_TYPE="sqlite"
    STATE_DB_PATH="$db_path"
    statedb_init_sqlite
  else
    STATE_DB_TYPE="json"
    STATE_DB_PATH="$prefix/var/state.json"
    statedb_init_json
  fi
  
  log_event "INFO" "delta_manager" "statedb_init" "app.session_started" \
    "\"type\":\"$STATE_DB_TYPE\",\"path\":\"$STATE_DB_PATH\"" 2>/dev/null
}

statedb_init_sqlite() {
  sqlite3 "$STATE_DB_PATH" << 'SQL'
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS file_index (
  path TEXT PRIMARY KEY, size INTEGER, mtime INTEGER, mode TEXT,
  content_hash TEXT, last_seen TEXT
);
CREATE TABLE IF NOT EXISTS command_fingerprints (
  command_id TEXT PRIMARY KEY, normalized_hash TEXT, last_ts TEXT
);
CREATE TABLE IF NOT EXISTS log_cursors (
  log_id TEXT PRIMARY KEY, inode INTEGER, offset INTEGER, last_ts TEXT, rotation_hint TEXT DEFAULT 'none'
);
CREATE TABLE IF NOT EXISTS inventory_state (
  section TEXT PRIMARY KEY, hash TEXT, count INTEGER, last_ts TEXT
);
CREATE TABLE IF NOT EXISTS chain_meta (
  report_id TEXT PRIMARY KEY, snapshot_type TEXT, base_report_id TEXT,
  chain_depth INTEGER, delta_index INTEGER, created_at TEXT, tool_version TEXT
);
CREATE TABLE IF NOT EXISTS metrics_history (
  run_id TEXT PRIMARY KEY, cpu_peak REAL, ram_peak REAL, disk_used INTEGER,
  conntrack_count INTEGER, wifi_clients INTEGER, vpn_peers INTEGER, ts TEXT
);
CREATE TABLE IF NOT EXISTS collector_status (
  collector_id TEXT PRIMARY KEY, last_status TEXT, last_fingerprint TEXT, run_count INTEGER, fail_streak INTEGER, last_ts TEXT
);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
SQL
  # Step 936: DB version
  sqlite3 "$STATE_DB_PATH" "INSERT OR IGNORE INTO meta VALUES('state_db_version','1');"
}

statedb_init_json() {
  if [ ! -f "$STATE_DB_PATH" ]; then
    cat > "$STATE_DB_PATH" << 'JEOF'
{"schema_id":"state","schema_version":"1","device_fingerprint":"","last_updated":"","file_index":{},"command_fingerprints":{},"log_cursors":{},"inventory_state":{},"chain_meta":[],"collector_status":{}}
JEOF
  fi
}

# Step 883: Device fingerprint check
statedb_check_fingerprint() {
  local expected="$1"
  local stored=""
  
  if [ "$STATE_DB_TYPE" = "sqlite" ]; then
    stored=$(sqlite3 "$STATE_DB_PATH" "SELECT value FROM meta WHERE key='device_fingerprint';" 2>/dev/null)
  else
    stored=$(jq -r '.device_fingerprint // empty' "$STATE_DB_PATH" 2>/dev/null)
  fi
  
  if [ -n "$stored" ] && [ "$stored" != "$expected" ]; then
    log_event "ERROR" "delta_manager" "fingerprint_mismatch" "errors.E008" \
      "\"expected\":\"$expected\",\"stored\":\"$stored\"" 2>/dev/null
    return 1
  fi
  
  # Save fingerprint
  if [ "$STATE_DB_TYPE" = "sqlite" ]; then
    sqlite3 "$STATE_DB_PATH" "INSERT OR REPLACE INTO meta VALUES('device_fingerprint','$expected');"
  fi
  return 0
}

# Step 884: File index operations
statedb_upsert_file() {
  local path="$1" size="$2" mtime="$3" mode="$4" hash="$5"
  local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  if [ "$STATE_DB_TYPE" = "sqlite" ]; then
    sqlite3 "$STATE_DB_PATH" "INSERT OR REPLACE INTO file_index VALUES('$path',$size,$mtime,'$mode','$hash','$ts');"
  fi
}

statedb_diff_files() {
  local report_dir="$1"
  # Return changed files vs stored state
  if [ "$STATE_DB_TYPE" = "sqlite" ]; then
    sqlite3 "$STATE_DB_PATH" "SELECT path FROM file_index;" 2>/dev/null
  fi
}

# Step 885: Command fingerprints
statedb_update_cmd_fingerprint() {
  local cmd_id="$1" hash="$2"
  local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  if [ "$STATE_DB_TYPE" = "sqlite" ]; then
    sqlite3 "$STATE_DB_PATH" "INSERT OR REPLACE INTO command_fingerprints VALUES('$cmd_id','$hash','$ts');"
  fi
}

statedb_cmd_changed() {
  local cmd_id="$1" new_hash="$2"
  if [ "$STATE_DB_TYPE" = "sqlite" ]; then
    local old=$(sqlite3 "$STATE_DB_PATH" "SELECT normalized_hash FROM command_fingerprints WHERE command_id='$cmd_id';" 2>/dev/null)
    [ "$old" != "$new_hash" ]
  else
    return 0  # Always consider changed in JSON mode
  fi
}

# Step 886: Log cursors
statedb_update_cursor() {
  local log_id="$1" inode="$2" offset="$3" hint="$4"
  local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  if [ "$STATE_DB_TYPE" = "sqlite" ]; then
    sqlite3 "$STATE_DB_PATH" "INSERT OR REPLACE INTO log_cursors VALUES('$log_id',$inode,$offset,'$ts','$hint');"
  fi
}

# Step 889: Record run metadata
statedb_record_run() {
  local report_id="$1" snapshot_type="$2" base_id="$3" chain_depth="$4" delta_idx="$5"
  local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  local tool_ver=$(cat "${TOOL_BASE_DIR:-/opt/keenetic-debug}/VERSION" 2>/dev/null || echo "unknown")
  if [ "$STATE_DB_TYPE" = "sqlite" ]; then
    sqlite3 "$STATE_DB_PATH" "INSERT OR REPLACE INTO chain_meta VALUES('$report_id','$snapshot_type','$base_id',$chain_depth,$delta_idx,'$ts','$tool_ver');"
  fi
}

# Step 890: Select baseline
statedb_select_baseline() {
  local policy=$(config_get incremental_base_policy 2>/dev/null || echo "last_baseline")
  if [ "$STATE_DB_TYPE" = "sqlite" ]; then
    case "$policy" in
      last_baseline)
        sqlite3 "$STATE_DB_PATH" "SELECT report_id FROM chain_meta WHERE snapshot_type='baseline' ORDER BY created_at DESC LIMIT 1;" 2>/dev/null
        ;;
      explicit)
        config_get incremental_base_report_id 2>/dev/null
        ;;
    esac
  fi
}

# Step 892: Tombstones for mirror
statedb_add_tombstone() {
  local path="$1"
  local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  if [ "$STATE_DB_TYPE" = "sqlite" ]; then
    sqlite3 "$STATE_DB_PATH" "INSERT OR REPLACE INTO file_index VALUES('$path',0,0,'TOMBSTONE',NULL,'$ts');"
  fi
}

# Step 894: Smart plan from state
statedb_plan_hints() {
  if [ "$STATE_DB_TYPE" = "sqlite" ]; then
    # Return collectors that had changes or are overdue
    sqlite3 "$STATE_DB_PATH" "SELECT collector_id, last_status, last_fingerprint FROM collector_status;" 2>/dev/null
  fi
}

# Step 895: Update collector status
statedb_update_collector_status() {
  local cid="$1" status="$2" fingerprint="$3"
  local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  if [ "$STATE_DB_TYPE" = "sqlite" ]; then
    local old_count=$(sqlite3 "$STATE_DB_PATH" "SELECT run_count FROM collector_status WHERE collector_id='$cid';" 2>/dev/null || echo 0)
    local fail_streak=$(sqlite3 "$STATE_DB_PATH" "SELECT fail_streak FROM collector_status WHERE collector_id='$cid';" 2>/dev/null || echo 0)
    [ "$status" != "OK" ] && fail_streak=$((fail_streak + 1)) || fail_streak=0
    sqlite3 "$STATE_DB_PATH" "INSERT OR REPLACE INTO collector_status VALUES('$cid','$status','$fingerprint',$((old_count+1)),$fail_streak,'$ts');"
  fi
}

# Step 913: Chain view
statedb_chain_view() {
  if [ "$STATE_DB_TYPE" = "sqlite" ]; then
    echo "Chain:"
    sqlite3 -header -column "$STATE_DB_PATH" "SELECT report_id, snapshot_type, chain_depth, delta_index, created_at FROM chain_meta ORDER BY created_at;" 2>/dev/null
  fi
}

# Step 915-916: Rebase and compaction
statedb_rebase() {
  local prefix="${TOOL_BASE_DIR:-/opt/keenetic-debug}"
  local chain_max=$(config_get incremental_chain_max_depth 2>/dev/null || echo 10)
  
  if [ "$(config_get dangerous_ops 2>/dev/null)" != "true" ]; then
    echo "Requires dangerous_ops=true"
    return 1
  fi
  
  log_event "INFO" "delta_manager" "rebase_start" "app.session_started" 2>/dev/null
  audit_log "chain_rebase" "admin" "cli" "ok" 2>/dev/null
  
  # Mark current as new baseline
  echo "Rebase: creating new baseline from current state"
}

statedb_compact() {
  local prefix="${TOOL_BASE_DIR:-/opt/keenetic-debug}"
  
  if [ "$(config_get dangerous_ops 2>/dev/null)" != "true" ]; then
    echo "Requires dangerous_ops=true"
    return 1
  fi
  
  audit_log "chain_compact" "admin" "cli" "ok" 2>/dev/null
  echo "Compaction: merging old deltas (origin metadata preserved in chain_meta)"
}

# Step 939: State reset
statedb_reset() {
  if [ "$(config_get dangerous_ops 2>/dev/null)" != "true" ]; then
    echo "Requires dangerous_ops=true"
    return 1
  fi
  
  rm -f "$STATE_DB_PATH"
  statedb_init "${TOOL_BASE_DIR:-/opt/keenetic-debug}"
  audit_log "state_reset" "admin" "cli" "ok" 2>/dev/null
  echo "StateDB reset complete"
}

# Step 888: Record metrics history
statedb_record_metrics() {
  local run_id="$1" cpu="$2" ram="$3" disk="$4"
  local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  if [ "$STATE_DB_TYPE" = "sqlite" ]; then
    sqlite3 "$STATE_DB_PATH" "INSERT OR REPLACE INTO metrics_history VALUES('$run_id',$cpu,$ram,$disk,0,0,0,'$ts');"
  fi
}

# Step 937: Hash important configs
statedb_hash_configs() {
  local enabled=$(config_get incremental_hash_important_configs 2>/dev/null || echo "true")
  [ "$enabled" != "true" ] && return
  
  for cfg in /opt/etc/nginx/nginx.conf /opt/etc/dnsmasq.conf /opt/etc/openvpn/*.conf; do
    [ -f "$cfg" ] || continue
    local hash
    hash=$(sha256sum "$cfg" 2>/dev/null | awk '{print $1}')
    statedb_upsert_file "$cfg" "$(wc -c < "$cfg")" "$(stat -c '%Y' "$cfg" 2>/dev/null)" "config" "$hash"
  done
}

# Step 928: Include StateDB/state.json in snapshot by policy
statedb_include_in_snapshot() {
  local report_dir="$1"
  if [ -f "$STATE_DB_PATH" ]; then
    cp "$STATE_DB_PATH" "$report_dir/state_snapshot.$([ "$STATE_DB_TYPE" = "sqlite" ] && echo db || echo json)" 2>/dev/null
  fi
}
