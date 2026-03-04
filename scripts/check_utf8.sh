#!/bin/sh
# Verify all JSON/MD/CSV files are valid UTF-8 without BOM
set -e
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
errors=0

echo "Checking UTF-8 encoding..."
find "$PROJECT_DIR" -type f \( -name '*.json' -o -name '*.md' -o -name '*.csv' -o -name '*.sh' \) \
  ! -path '*/.git/*' ! -path '*/node_modules/*' | while read -r f; do
  # Check for BOM
  if head -c 3 "$f" | od -An -tx1 | grep -q 'ef bb bf'; then
    echo "FAIL: $f has UTF-8 BOM"
    echo "FAIL" > /tmp/utf8_errors
  fi
  # Check valid UTF-8 (if iconv available)
  if command -v iconv >/dev/null 2>&1; then
    if ! iconv -f UTF-8 -t UTF-8 "$f" >/dev/null 2>&1; then
      echo "FAIL: $f is not valid UTF-8"
      echo "FAIL" > /tmp/utf8_errors
    fi
  fi
done

if [ -f /tmp/utf8_errors ]; then
  rm -f /tmp/utf8_errors
  exit 1
fi
echo "OK: All files are valid UTF-8"
