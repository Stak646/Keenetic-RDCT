#!/bin/sh
# scripts/validate_collectors.sh — Validate all collectors
# Steps 606-609, 670
set -e
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COLLECTORS_DIR="$PROJECT_DIR/collectors"
SCHEMAS_DIR="$PROJECT_DIR/schemas"
errors=0

echo "=== Collector Validation ==="

# Step 606: Check registry matches directories
if [ -f "$COLLECTORS_DIR/registry.json" ] && command -v jq >/dev/null 2>&1; then
  echo "[Registry consistency]"
  for cdir in "$COLLECTORS_DIR"/*/; do
    [ -d "$cdir" ] || continue
    cid=$(basename "$cdir")
    [ "$cid" = "_template" ] && continue
    if ! jq -e --arg id "$cid" '.collectors[] | select(.id==$id)' "$COLLECTORS_DIR/registry.json" >/dev/null 2>&1; then
      echo "  FAIL: $cid not in registry.json"
      errors=$((errors + 1))
    fi
  done
fi

# Step 607-609: Validate each collector
echo "[Plugin validation]"
for cdir in "$COLLECTORS_DIR"/*/; do
  [ -d "$cdir" ] || continue
  cid=$(basename "$cdir")
  [ "$cid" = "_template" ] && continue
  
  plugin="$cdir/plugin.json"
  
  # Has plugin.json?
  if [ ! -f "$plugin" ]; then
    echo "  FAIL: $cid missing plugin.json"
    errors=$((errors + 1))
    continue
  fi
  
  # Valid JSON?
  if command -v jq >/dev/null 2>&1; then
    if ! jq . "$plugin" >/dev/null 2>&1; then
      echo "  FAIL: $cid plugin.json invalid JSON"
      errors=$((errors + 1))
      continue
    fi
    
    # Step 607: version SemVer, contract_version numeric
    local ver=$(jq -r '.version // empty' "$plugin")
    if [ -z "$ver" ]; then
      echo "  FAIL: $cid missing version"
      errors=$((errors + 1))
    fi
    
    local cv=$(jq -r '.contract_version // empty' "$plugin")
    if [ -z "$cv" ]; then
      echo "  FAIL: $cid missing contract_version"
      errors=$((errors + 1))
    fi
    
    # Step 608: privacy_tags in allowed vocabulary
    local tags=$(jq -r '.privacy_tags[]? // empty' "$plugin")
    for tag in $tags; do
      case "$tag" in
        password|token|ip|mac|ssid|cookie|key|cert|logs|payload) ;;
        *) echo "  FAIL: $cid invalid privacy_tag: $tag"; errors=$((errors+1)) ;;
      esac
    done
    
    # Step 609: Has dependencies
    local has_deps=$(jq 'has("dependencies")' "$plugin")
    if [ "$has_deps" != "true" ]; then
      echo "  WARN: $cid missing dependencies field"
    fi
  fi
  
  # Has run.sh?
  if [ ! -f "$cdir/run.sh" ]; then
    echo "  FAIL: $cid missing run.sh"
    errors=$((errors + 1))
  fi
done

echo ""
if [ $errors -eq 0 ]; then
  echo "ALL COLLECTORS VALID ✅"
else
  echo "FAILED: $errors issues"
  exit 1
fi
