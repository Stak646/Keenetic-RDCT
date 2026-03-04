#!/bin/sh
# Test runner for keenetic-debug
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== keenetic-debug test suite ==="

echo "[1/5] Schema validation..."
"$SCRIPT_DIR/validate_schemas.sh" || { echo "FAIL: schemas"; exit 1; }

echo "[2/5] L10n coverage..."
"$SCRIPT_DIR/check_l10n_coverage.sh" || { echo "FAIL: l10n"; exit 1; }

echo "[3/5] Required docs..."
"$SCRIPT_DIR/check_required_docs.sh" || { echo "FAIL: docs"; exit 1; }

echo "[4/5] UTF-8 check..."
"$SCRIPT_DIR/check_utf8.sh" || { echo "FAIL: utf8"; exit 1; }

echo "[5/5] Safe defaults..."
"$SCRIPT_DIR/check_no_wan_bind_defaults.sh" || { echo "FAIL: safe defaults"; exit 1; }

echo ""
echo "=== ALL TESTS PASSED ==="
