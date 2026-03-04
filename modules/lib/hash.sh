#!/bin/sh
# modules/lib/hash.sh — Unified SHA256 (sha256sum / openssl fallback)
# Step 621

compute_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 -r "$file" | awk '{print $1}'
  else
    echo "NO_SHA256_TOOL"
    return 1
  fi
}

compute_sha256_string() {
  local str="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    echo "$str" | sha256sum | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    echo "$str" | openssl dgst -sha256 -r | awk '{print $1}'
  else
    echo "NO_SHA256_TOOL"
  fi
}
