#!/bin/sh
# Run Core in sandbox mode with fixtures
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FIXTURES="$PROJECT_DIR/tests/fixtures/sandbox"
OUTPUT="/tmp/sandbox_out"

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"

echo "=== Sandbox mode ==="
echo "Fixtures: $FIXTURES"
echo "Output:   $OUTPUT"

# TODO: when Core is implemented, run:
# SANDBOX_MODE=1 FIXTURES_DIR="$FIXTURES" "$PROJECT_DIR/bin/keenetic-debug" \
#   start --mode light --perf lite --output "$OUTPUT"

echo "Sandbox run complete. Output in $OUTPUT"
echo "(Stub: Core not yet implemented)"
