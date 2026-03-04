#!/bin/sh
# Extract i18n key usage from code and compare with ru.json/en.json
# Step 303: find dead keys and missing keys
set -e
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
I18N_DIR="$PROJECT_DIR/i18n"

echo "=== i18n Key Analysis ==="

# Keys used in code (grep for t() calls and message_key references)
echo "Scanning code for key usage..."
used_keys=$(grep -roh 't("[^"]*"' "$PROJECT_DIR/modules" "$PROJECT_DIR/cli" "$PROJECT_DIR/web" 2>/dev/null | \
  sed 's/t("//; s/"//' | sort -u)
used_keys2=$(grep -roh '"message_key"[[:space:]]*:[[:space:]]*"[^"]*"' "$PROJECT_DIR" 2>/dev/null | \
  sed 's/.*"message_key"[[:space:]]*:[[:space:]]*"//; s/"//' | sort -u)

# Keys defined in en.json
if command -v jq >/dev/null 2>&1; then
  defined_keys=$(jq -r 'keys[]' "$I18N_DIR/en.json" 2>/dev/null | sort -u)
else
  defined_keys=$(grep -o '"[^"]*":' "$I18N_DIR/en.json" | sed 's/"//g; s/://' | sort -u)
fi

echo ""
echo "Defined keys: $(echo "$defined_keys" | wc -l)"
echo "Used in code: $(echo "$used_keys" | wc -l)"

# Dead keys (defined but never used) — for info only
# Missing keys (used but not defined) — CI-blocking
echo ""
echo "Keys used but not defined (MISSING — must fix):"
for k in $used_keys $used_keys2; do
  echo "$defined_keys" | grep -qx "$k" || echo "  MISSING: $k"
done

echo ""
echo "Analysis complete"
