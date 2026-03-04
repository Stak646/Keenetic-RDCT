#!/bin/sh
# Generate release-manifest.json with pinned sha256 for all release artifacts
set -e
VERSION=$(cat version.json | grep '"version"' | sed 's/.*: *"\(.*\)".*/\1/')

echo "{"
echo "  \"version\": \"$VERSION\","
echo "  \"date\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
echo "  \"artifacts\": ["

first=1
for f in release-*/keenetic-debug-*.tar.gz; do
  [ -f "$f" ] || continue
  hash=$(sha256sum "$f" | awk '{print $1}')
  size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
  [ $first -eq 0 ] && echo "    ,"
  echo "    {"
  echo "      \"file\": \"$(basename "$f")\","
  echo "      \"sha256\": \"$hash\","
  echo "      \"size\": $size"
  echo "    }"
  first=0
done

echo "  ]"
echo "}"
