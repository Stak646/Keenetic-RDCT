#!/bin/sh
# scripts/gen_version.sh
# Single source of truth for version (from version.json + git)
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$ROOT_DIR/version.json"

VERSION=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['version'])" 2>/dev/null || echo "unknown")

# Try to get git info
GIT_COMMIT=""
GIT_TAG=""
if command -v git >/dev/null 2>&1 && [ -d "$ROOT_DIR/.git" ]; then
  GIT_COMMIT=$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "")
  GIT_TAG=$(git -C "$ROOT_DIR" describe --tags --exact-match 2>/dev/null || echo "")
fi

# If git tag exists, use it as version
if [ -n "$GIT_TAG" ]; then
  VERSION="$GIT_TAG"
fi

# Build string
BUILD=""
if [ -n "$GIT_COMMIT" ]; then
  BUILD="+$GIT_COMMIT"
fi

echo "${VERSION}${BUILD}"
