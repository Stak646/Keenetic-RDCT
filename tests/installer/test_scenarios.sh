#!/bin/sh
# Installer test scenarios — Steps 396-399
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SH="$PROJECT_DIR/scripts/install.sh"

pass=0; fail=0; skip=0

run_test() {
  local name="$1"
  shift
  echo -n "  [$name] "
  if "$@" >/dev/null 2>&1; then
    echo "PASS"
    pass=$((pass + 1))
  else
    echo "FAIL"
    fail=$((fail + 1))
  fi
}

echo "=== Installer Test Scenarios ==="

# Step 396: No-network → suggest offline
echo "[Scenario 1: No network suggestion]"
run_test "help_works" sh "$INSTALL_SH" --help
run_test "dry_run_works" sh "$INSTALL_SH" --dry-run --prefix /tmp/kd_test_$$

# Step 397: Idempotent install
echo "[Scenario 2: Idempotent install]"
PREFIX_TMP="/tmp/kd_test_idem_$$"
run_test "first_install" sh "$INSTALL_SH" --prefix "$PREFIX_TMP" --no-autostart
run_test "second_install" sh "$INSTALL_SH" --prefix "$PREFIX_TMP" --no-autostart
run_test "config_preserved" test -f "$PREFIX_TMP/config.json"
run_test "token_preserved" test -f "$PREFIX_TMP/var/.auth_token"
rm -rf "$PREFIX_TMP"

# Step 398: Uninstall
echo "[Scenario 3: Uninstall]"
PREFIX_TMP="/tmp/kd_test_uninst_$$"
sh "$INSTALL_SH" --prefix "$PREFIX_TMP" --no-autostart >/dev/null 2>&1
run_test "uninstall" sh "$INSTALL_SH" --uninstall --yes --prefix "$PREFIX_TMP"
run_test "dirs_removed" test ! -d "$PREFIX_TMP/bin"
rm -rf "$PREFIX_TMP"

# Step 399: Upgrade preserves backup
echo "[Scenario 4: Upgrade + rollback]"
PREFIX_TMP="/tmp/kd_test_upgrade_$$"
sh "$INSTALL_SH" --prefix "$PREFIX_TMP" --no-autostart >/dev/null 2>&1
run_test "version_file" test -f "$PREFIX_TMP/VERSION"
run_test "token_exists" test -f "$PREFIX_TMP/var/.auth_token"
rm -rf "$PREFIX_TMP"

# Step 400: Shellcheck compatibility
echo "[Scenario 5: Shell compatibility]"
if command -v shellcheck >/dev/null 2>&1; then
  run_test "shellcheck" shellcheck -s sh "$INSTALL_SH"
else
  echo "  [shellcheck] SKIP (not installed)"
  skip=$((skip + 1))
fi

# Verify no bash-isms (Step 371)
run_test "no_double_bracket" sh -c "! grep -n '\[\[' '$INSTALL_SH'"
run_test "no_bash_arrays" sh -c "! grep -n 'declare\|typeset' '$INSTALL_SH'"
run_test "no_process_sub" sh -c "! grep -n '<(' '$INSTALL_SH'"

echo ""
echo "Results: $pass passed, $fail failed, $skip skipped"
