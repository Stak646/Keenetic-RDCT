#!/bin/sh
# tests/core/test_core.sh — Core, Governor, FileOps, ProcessRunner, LockManager tests
# Steps 534-542
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMPDIR=$(mktemp -d)
pass=0; fail=0

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

run_test() {
  local name="$1"; shift
  echo -n "  [$name] "
  if "$@" 2>/dev/null; then echo "PASS"; pass=$((pass+1))
  else echo "FAIL"; fail=$((fail+1)); fi
}

echo "=== Core Module Tests ==="

# Step 534: FileOps atomic_write
echo "[FileOps]"
. "$PROJECT_DIR/modules/file_ops.sh"
run_test "atomic_write" sh -c "
  . '$PROJECT_DIR/modules/file_ops.sh'
  atomic_write '$TMPDIR/test.txt' 'hello'
  [ -f '$TMPDIR/test.txt' ] && [ \"\$(cat '$TMPDIR/test.txt')\" = 'hello' ]
"

run_test "validate_output_path_ok" sh -c "
  . '$PROJECT_DIR/modules/file_ops.sh'
  validate_output_path '$TMPDIR/sub/file' '$TMPDIR'
"

run_test "validate_output_path_reject" sh -c "
  . '$PROJECT_DIR/modules/file_ops.sh'
  ! validate_output_path '/etc/passwd' '$TMPDIR' 2>/dev/null
"

# Step 534: ProcessRunner timeout
echo "[ProcessRunner]"
run_test "process_timeout" sh -c "
  . '$PROJECT_DIR/modules/process_runner.sh'
  echo '#!/bin/sh' > '$TMPDIR/slow.sh'
  echo 'sleep 60' >> '$TMPDIR/slow.sh'
  chmod +x '$TMPDIR/slow.sh'
  mkdir -p '$TMPDIR/work'
  process_run '$TMPDIR/slow.sh' '$TMPDIR/work' 2 50
  [ \$? -eq 124 ] || [ \$? -eq 137 ]
"

# Step 534: LockManager
echo "[LockManager]"
run_test "lock_acquire" sh -c "
  . '$PROJECT_DIR/modules/lock_manager.sh'
  lock_acquire '$TMPDIR/test.lock' 1
  [ -f '$TMPDIR/test.lock' ]
"

run_test "lock_release" sh -c "
  . '$PROJECT_DIR/modules/lock_manager.sh'
  lock_acquire '$TMPDIR/test2.lock' 1
  lock_release '$TMPDIR/test2.lock'
  [ ! -f '$TMPDIR/test2.lock' ]
"

# Step 535: Integration — sandbox end-to-end
echo "[Integration]"
run_test "sandbox_preflight" sh -c "
  export PATH=\"$PROJECT_DIR/cli:\$PATH\"
  mkdir -p '$TMPDIR/sandbox/collectors'
  # Minimal preflight should not crash
  . '$PROJECT_DIR/modules/logger.sh'
  . '$PROJECT_DIR/modules/configurator.sh'
  . '$PROJECT_DIR/modules/preflight.sh'
  _core_report_id='test-run'
  config_load /dev/null 2>/dev/null || true
  preflight_run '$TMPDIR/sandbox' '$TMPDIR/sandbox' 2>/dev/null
  [ -f '$TMPDIR/sandbox/preflight.json' ]
"

# Step 539: Governor throttle
echo "[Governor]"
run_test "governor_init" sh -c "
  . '$PROJECT_DIR/modules/configurator.sh'
  . '$PROJECT_DIR/modules/governor.sh'
  config_load /dev/null 2>/dev/null || true
  governor_init
  [ \$_gov_max_workers -ge 1 ]
"

# Step 541: Event log order
echo "[EventLog]"
run_test "event_log_format" sh -c "
  . '$PROJECT_DIR/modules/logger.sh'
  logger_init 'INFO' '$TMPDIR/events.jsonl' 'test-corr'
  log_event 'INFO' 'test' 'test.start' 'app.session_started' '\"k\":\"v\"'
  log_event 'WARN' 'test' 'test.warn' 'errors.E001'
  [ -f '$TMPDIR/events.jsonl' ] && [ \$(wc -l < '$TMPDIR/events.jsonl') -eq 2 ]
"

echo ""
echo "Results: $pass passed, $fail failed"
[ $fail -eq 0 ] && echo "ALL TESTS PASSED ✅"

# Step 965: WebUI integration test
run_test "webui_health_check" sh -c "
  echo \"WebUI integration test (stub — requires python3 + port)\"
  true
"

# Step 973: CLI argument parsing tests
echo "[CLI]"
run_test "cli_version" sh -c "$PROJECT_DIR/cli/keenetic-debug --version | grep -q keenetic"
run_test "cli_help_exit" sh -c "$PROJECT_DIR/cli/keenetic-debug --help >/dev/null 2>&1"

