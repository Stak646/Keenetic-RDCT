#!/bin/sh
# Verify all schema files are in registry and schema_ids are unique
set -e
SCHEMAS_DIR="$(cd "$(dirname "$0")/../schemas" && pwd)"
errors=0

echo "Checking schema registry..."

# Check all .schema.json files exist
for schema_file in "$SCHEMAS_DIR"/*.schema.json; do
  [ -f "$schema_file" ] || continue
  basename_f="$(basename "$schema_file")"
  schema_id=$(grep -o '"schema_id"' "$schema_file" 2>/dev/null || true)
  if [ -z "$schema_id" ]; then
    # Check if it has $id instead (meta-level schemas)
    has_id=$(grep -c '"\$id"' "$schema_file" 2>/dev/null || echo 0)
    if [ "$has_id" -eq 0 ]; then
      echo "WARN: $basename_f has no \$id"
    fi
  fi
  # Verify listed in README
  if ! grep -q "$basename_f" "$SCHEMAS_DIR/README.md" 2>/dev/null; then
    echo "FAIL: $basename_f not in schemas/README.md"
    errors=$((errors + 1))
  fi
done

# Check for duplicate schema_ids
ids=$(grep -rh '"const":' "$SCHEMAS_DIR"/*.schema.json 2>/dev/null | sort)
dupes=$(echo "$ids" | uniq -d)
if [ -n "$dupes" ]; then
  echo "FAIL: Duplicate schema_ids: $dupes"
  errors=$((errors + 1))
fi

if [ $errors -gt 0 ]; then
  echo "FAILED: $errors schema registry issues"
  exit 1
fi
echo "OK: Schema registry consistent"
