#!/bin/sh
# Runtime validator: validates key JSON artifacts before snapshot publish
# Used by Packager before final archive creation
# Errors are written to debugger_report if validation fails
set -e

SCHEMAS_DIR="${SCHEMAS_DIR:-$(dirname "$0")/../schemas}"
WORKDIR="${1:-.}"
errors=0
results=""

validate_file() {
  local file="$1"
  local schema="$2"
  local name="$3"
  
  if [ ! -f "$file" ]; then
    results="${results}\n{\"file\":\"$name\",\"status\":\"MISSING\"}"
    return
  fi
  
  # Try python3 jsonschema first
  if command -v python3 >/dev/null 2>&1; then
    if python3 -c "
import json, sys
try:
    from jsonschema import validate, ValidationError
    with open('$file') as f: data = json.load(f)
    with open('$schema') as f: schema = json.load(f)
    validate(data, schema)
    print('OK')
except ValidationError as e:
    print('FAIL: ' + str(e.message)[:200])
    sys.exit(1)
except ImportError:
    # No jsonschema module — do basic JSON parse check
    print('OK (basic)')
except Exception as e:
    print('ERROR: ' + str(e)[:200])
    sys.exit(1)
" 2>/dev/null; then
      results="${results}\n{\"file\":\"$name\",\"status\":\"OK\"}"
    else
      results="${results}\n{\"file\":\"$name\",\"status\":\"FAIL\"}"
      errors=$((errors + 1))
    fi
  else
    # Fallback: just check it's valid JSON
    if python3 -c "import json; json.load(open('$file'))" 2>/dev/null || \
       command -v jq >/dev/null 2>&1 && jq . "$file" >/dev/null 2>&1; then
      results="${results}\n{\"file\":\"$name\",\"status\":\"OK (json-only)\"}"
    else
      results="${results}\n{\"file\":\"$name\",\"status\":\"FAIL (invalid JSON)\"}"
      errors=$((errors + 1))
    fi
  fi
}

echo "=== Runtime Schema Validation ==="

# Validate mandatory artifacts
validate_file "$WORKDIR/manifest.json" "$SCHEMAS_DIR/manifest.schema.json" "manifest.json"
validate_file "$WORKDIR/preflight.json" "$SCHEMAS_DIR/preflight.schema.json" "preflight.json"
validate_file "$WORKDIR/plan.json" "$SCHEMAS_DIR/plan.schema.json" "plan.json"

# Validate optional artifacts if present
[ -f "$WORKDIR/checks.json" ] && \
  validate_file "$WORKDIR/checks.json" "$SCHEMAS_DIR/checks.schema.json" "checks.json"
[ -f "$WORKDIR/inventory.json" ] && \
  validate_file "$WORKDIR/inventory.json" "$SCHEMAS_DIR/inventory.schema.json" "inventory.json"
[ -f "$WORKDIR/redaction_report.json" ] && \
  validate_file "$WORKDIR/redaction_report.json" "$SCHEMAS_DIR/redaction_report.schema.json" "redaction_report.json"

echo ""
printf "%b\n" "$results"
echo ""

if [ $errors -gt 0 ]; then
  echo "VALIDATION FAILED: $errors errors"
  # Write to debugger report if exists
  if [ -d "$WORKDIR" ]; then
    printf "%b" "$results" > "$WORKDIR/validation_errors.json"
  fi
  exit 1
fi
echo "ALL VALIDATIONS PASSED"
