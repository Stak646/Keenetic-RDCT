#!/bin/sh
# Verify safe defaults: no 0.0.0.0 bind, no dangerous_ops=true, readonly=true
set -e
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
errors=0

echo "Checking safe defaults..."

# Check config example
for cfg in "$PROJECT_DIR"/examples/config*.json; do
  [ -f "$cfg" ] || continue
  base="$(basename "$cfg")"
  
  if grep -q '"0\.0\.0\.0"' "$cfg"; then
    echo "FAIL: $base contains bind 0.0.0.0"
    errors=$((errors + 1))
  fi
  if grep -q '"dangerous_ops"[[:space:]]*:[[:space:]]*true' "$cfg"; then
    echo "FAIL: $base has dangerous_ops=true"
    errors=$((errors + 1))
  fi
  if grep -q '"readonly"[[:space:]]*:[[:space:]]*false' "$cfg"; then
    echo "FAIL: $base has readonly=false"
    errors=$((errors + 1))
  fi
done

# Check config schema defaults
schema="$PROJECT_DIR/schemas/config.schema.json"
if [ -f "$schema" ]; then
  if grep -q '"default"[[:space:]]*:[[:space:]]*"0\.0\.0\.0"' "$schema"; then
    echo "FAIL: config.schema.json has default 0.0.0.0"
    errors=$((errors + 1))
  fi
fi

if [ $errors -gt 0 ]; then
  echo "FAILED: $errors unsafe defaults found"
  exit 1
fi
echo "OK: All defaults are safe"
