#!/bin/sh
# Schema validation tests: positive (examples pass) + negative (bad data fails)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCHEMAS="$PROJECT_DIR/schemas"
EXAMPLES="$PROJECT_DIR/examples/artifacts"

pass=0; fail=0; skip=0

# Check if python3 with jsonschema is available
if ! python3 -c "import jsonschema" 2>/dev/null; then
  echo "SKIP: python3 jsonschema not available"
  echo "Install: pip install jsonschema"
  exit 0
fi

validate() {
  local example="$1"
  local schema="$2"
  local expect="$3"  # pass or fail
  local desc="$4"
  
  result=$(python3 -c "
import json, sys
from jsonschema import validate, ValidationError
with open('$example') as f: data = json.load(f)
with open('$schema') as f: schema = json.load(f)
try:
    validate(data, schema)
    print('PASS')
except ValidationError as e:
    print('FAIL: ' + e.message[:100])
" 2>&1)
  
  if [ "$expect" = "pass" ] && echo "$result" | grep -q "^PASS"; then
    pass=$((pass + 1))
  elif [ "$expect" = "fail" ] && echo "$result" | grep -q "^FAIL"; then
    pass=$((pass + 1))  # Expected failure = pass
  else
    echo "❌ $desc: expected=$expect got=$result"
    fail=$((fail + 1))
  fi
}

echo "=== Schema Validation Tests ==="

# Positive tests: examples should validate
validate "$EXAMPLES/manifest.example.json" "$SCHEMAS/manifest.schema.json" "pass" "manifest positive"
validate "$EXAMPLES/preflight.example.json" "$SCHEMAS/preflight.schema.json" "pass" "preflight positive"
validate "$EXAMPLES/plan.example.json" "$SCHEMAS/plan.schema.json" "pass" "plan positive"
validate "$EXAMPLES/checks.example.json" "$SCHEMAS/checks.schema.json" "pass" "checks positive"
validate "$EXAMPLES/redaction_report.example.json" "$SCHEMAS/redaction_report.schema.json" "pass" "redaction positive"
validate "$EXAMPLES/inventory.example.json" "$SCHEMAS/inventory.schema.json" "pass" "inventory positive"
validate "$EXAMPLES/inventory_delta.example.json" "$SCHEMAS/inventory_delta.schema.json" "pass" "inventory_delta positive"
validate "$EXAMPLES/state.example.json" "$SCHEMAS/state.schema.json" "pass" "state positive"
validate "$EXAMPLES/sbom.example.json" "$SCHEMAS/sbom.schema.json" "pass" "sbom positive"
validate "$EXAMPLES/result.example.json" "$SCHEMAS/result.schema.json" "pass" "result positive"

# Negative tests: bad data should fail
echo '{"invalid": true}' > /tmp/bad_manifest.json
validate "/tmp/bad_manifest.json" "$SCHEMAS/manifest.schema.json" "fail" "manifest negative (missing fields)"

echo '{"schema_id":"plan","schema_version":"1","report_id":"x","timestamp":"bad","research_mode":"invalid","performance_mode":"lite","snapshot_mode":"baseline","tasks":[]}' > /tmp/bad_plan.json
validate "/tmp/bad_plan.json" "$SCHEMAS/plan.schema.json" "fail" "plan negative (invalid enum)"

rm -f /tmp/bad_manifest.json /tmp/bad_plan.json

echo ""
echo "Results: $pass passed, $fail failed, $skip skipped"
[ $fail -eq 0 ] && echo "ALL TESTS PASSED ✅" || { echo "TESTS FAILED ❌"; exit 1; }
