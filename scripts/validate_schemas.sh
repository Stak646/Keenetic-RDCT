#!/bin/sh
# scripts/validate_schemas.sh
# Validate example JSON files against schemas (JSON Schema 2020-12)
# Usage: ./scripts/validate_schemas.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEMAS_DIR="$ROOT_DIR/schemas"
EXAMPLES_DIR="$ROOT_DIR/examples"

ERRORS=0

echo "=== Schema Validation ==="

# Check if validator is available
if command -v ajv >/dev/null 2>&1; then
  VALIDATOR="ajv"
elif command -v python3 -c "import jsonschema" 2>/dev/null; then
  VALIDATOR="python"
else
  echo "WARN: No JSON Schema validator found (ajv or python3 jsonschema)"
  echo "Install: npm install -g ajv-cli OR pip install jsonschema"
  exit 0
fi

validate_file() {
  local json_file="$1"
  local schema_file="$2"

  if [ "$VALIDATOR" = "ajv" ]; then
    if ajv validate -s "$schema_file" -d "$json_file" --spec=draft2020  2>/dev/null; then
      echo "  OK: $(basename "$json_file")"
    else
      echo "  FAIL: $(basename "$json_file")"
      ERRORS=$((ERRORS + 1))
    fi
  elif [ "$VALIDATOR" = "python" ]; then
    if python3 -c "
import json, jsonschema
with open('$schema_file') as f: schema = json.load(f)
with open('$json_file') as f: data = json.load(f)
jsonschema.validate(data, schema)
print('  OK: $(basename "$json_file")')
" 2>/dev/null; then
      :
    else
      echo "  FAIL: $(basename "$json_file")"
      ERRORS=$((ERRORS + 1))
    fi
  fi
}

# Validate examples against their schemas
for example in "$EXAMPLES_DIR"/artifacts/*.json; do
  [ -f "$example" ] || continue
  echo "Checking: $(basename "$example")"
  # Try to detect schema from file content
  schema_id=$(python3 -c "import json; d=json.load(open('$example')); print(d.get('schema_id',''))" 2>/dev/null || echo "")
  if [ -n "$schema_id" ]; then
    schema_file="$SCHEMAS_DIR/$(echo "$schema_id" | sed 's/keenetic-debug\.//' | sed 's/\./_/g').schema.json"
    if [ -f "$schema_file" ]; then
      validate_file "$example" "$schema_file"
    else
      echo "  SKIP: No schema found for $schema_id"
    fi
  fi
done

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS validation error(s)"
  exit 1
else
  echo "PASSED: All schemas valid"
fi
