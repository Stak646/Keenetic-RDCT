#!/bin/sh
# scripts/new_collector.sh — Generate new collector from template
# Step 605
set -eu

if [ $# -lt 1 ]; then
  echo "Usage: new_collector.sh <collector_id> [category]"
  echo "Example: new_collector.sh wifi.scan wifi"
  exit 1
fi

CID="$1"
CATEGORY="${2:-misc}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$PROJECT_DIR/collectors/_template"
TARGET="$PROJECT_DIR/collectors/$CID"

if [ -d "$TARGET" ]; then
  echo "ERROR: Collector $CID already exists"
  exit 1
fi

mkdir -p "$TARGET"
cp "$TEMPLATE/plugin.json" "$TARGET/plugin.json"
cp "$TEMPLATE/run.sh" "$TARGET/run.sh"
chmod +x "$TARGET/run.sh"

# Replace placeholders
sed -i "s/COLLECTOR_ID/$CID/g" "$TARGET/plugin.json" "$TARGET/run.sh"
sed -i "s/COLLECTOR_NAME/$CID collector/g" "$TARGET/plugin.json" "$TARGET/run.sh"
sed -i "s/CATEGORY/$CATEGORY/g" "$TARGET/plugin.json" "$TARGET/run.sh"

# Update registry
if command -v jq >/dev/null 2>&1 && [ -f "$PROJECT_DIR/collectors/registry.json" ]; then
  jq --arg id "$CID" --arg cat "$CATEGORY" \
    '.collectors += [{"id":$id,"path":$id,"category":$cat,"phase":$cat}]' \
    "$PROJECT_DIR/collectors/registry.json" > "$PROJECT_DIR/collectors/registry.json.tmp" && \
    mv "$PROJECT_DIR/collectors/registry.json.tmp" "$PROJECT_DIR/collectors/registry.json"
fi

echo "Created: $TARGET"
echo "Files: plugin.json, run.sh"
echo "Next: edit plugin.json and run.sh, then run CI checks"
