#!/bin/sh
# scripts/check_l10n_coverage.sh
# Verify RU and EN localization files have identical key sets
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
I18N_DIR="$ROOT_DIR/i18n"

RU_FILE="$I18N_DIR/ru.json"
EN_FILE="$I18N_DIR/en.json"

echo "=== L10N Coverage Check ==="

if [ ! -f "$RU_FILE" ] || [ ! -f "$EN_FILE" ]; then
  echo "FAIL: Missing i18n files"
  exit 1
fi

# Extract and sort keys (excluding _meta)
extract_keys() {
  python3 -c "
import json, sys
with open('$1') as f:
    data = json.load(f)
keys = sorted(k for k in data.keys() if not k.startswith('_'))
for k in keys:
    print(k)
"
}

RU_KEYS=$(extract_keys "$RU_FILE")
EN_KEYS=$(extract_keys "$EN_FILE")

# Compare
RU_ONLY=$(comm -23 <(echo "$RU_KEYS") <(echo "$EN_KEYS") 2>/dev/null || true)
EN_ONLY=$(comm -13 <(echo "$RU_KEYS") <(echo "$EN_KEYS") 2>/dev/null || true)

ERRORS=0

if [ -n "$RU_ONLY" ]; then
  echo "Keys in RU but missing in EN:"
  echo "$RU_ONLY" | sed 's/^/  - /'
  ERRORS=$((ERRORS + 1))
fi

if [ -n "$EN_ONLY" ]; then
  echo "Keys in EN but missing in RU:"
  echo "$EN_ONLY" | sed 's/^/  - /'
  ERRORS=$((ERRORS + 1))
fi

RU_COUNT=$(echo "$RU_KEYS" | wc -l | tr -d ' ')
EN_COUNT=$(echo "$EN_KEYS" | wc -l | tr -d ' ')
echo "RU keys: $RU_COUNT | EN keys: $EN_COUNT"

if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: L10N key mismatch"
  exit 1
else
  echo "PASSED: L10N coverage 100% ($RU_COUNT keys)"
fi
