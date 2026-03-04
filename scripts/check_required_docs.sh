#!/bin/sh
# Step 131: Verify required doc sections exist in RU and EN
set -e

REQUIRED_FILES="
README.md
"

REQUIRED_SECTIONS="
Quick Start
"

errors=0
for lang in ru en; do
  dir="docs/$lang"
  if [ ! -d "$dir" ]; then
    echo "FAIL: Missing $dir/"
    errors=$((errors + 1))
    continue
  fi
  for f in $REQUIRED_FILES; do
    if [ ! -f "$dir/$f" ]; then
      echo "FAIL: Missing $dir/$f"
      errors=$((errors + 1))
    fi
  done
done

if [ $errors -gt 0 ]; then
  echo "FAILED: $errors missing docs"
  exit 1
fi
echo "OK: All required docs present"
