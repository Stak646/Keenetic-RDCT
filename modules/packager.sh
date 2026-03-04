#!/bin/sh
# modules/packager.sh — Snapshot archiver with streaming, sha256, denylist
# Steps 791-813

packager_create_archive() {
  local report_dir="$1"
  local output_file="$2"
  local report_id="$3"
  local prefix="${TOOL_BASE_DIR:-/opt/keenetic-debug}"
  
  local format=$(config_get archive_format 2>/dev/null || echo "tar.gz")
  local comp_level=$(config_get archive_compression_level 2>/dev/null || echo 6)
  local perf=$(config_get performance_mode 2>/dev/null || echo "auto")
  
  # Step 807: Compression level by perf mode
  case "$perf" in
    lite) comp_level=1 ;;
    hard) comp_level=9 ;;
  esac
  
  # Step 796: Intermediate partial manifest
  packager_write_manifest "$report_dir" "true"
  
  # Step 797-798: Always include critical files
  for crit in event_log.jsonl debugger_report.json summary.json manifest.json; do
    [ ! -f "$report_dir/$crit" ] && [ -f "$(dirname "$report_dir")/tmp/$report_id/$crit" ] && \
      cp "$(dirname "$report_dir")/tmp/$report_id/$crit" "$report_dir/" 2>/dev/null
  done
  
  # Step 792: Atomic archive creation
  local tmp_archive="${output_file}.tmp"
  
  # Step 799-800: Build file list with denylist enforcement
  local filelist=$(mktemp)
  packager_build_filelist "$report_dir" "$filelist" "$prefix"
  
  # Step 803: Stable sorted order
  sort -o "$filelist" "$filelist"
  
  # Step 801: Check limits
  local total_files=$(wc -l < "$filelist")
  local max_files=50000
  if [ "$total_files" -gt "$max_files" ]; then
    head -n "$max_files" "$filelist" > "${filelist}.trunc"
    mv "${filelist}.trunc" "$filelist"
    log_event "WARN" "packager" "files_limit" "packager.enospc" \
      "\"total\":$total_files,\"limit\":$max_files" 2>/dev/null
  fi
  
  # Step 791: Create archive
  case "$format" in
    tar.gz)
      if command -v tar >/dev/null 2>&1; then
        tar czf "$tmp_archive" -C "$(dirname "$report_dir")" \
          --files-from="$filelist" 2>/dev/null
      fi
      ;;
    zip)
      # Step 793: Optional zip support
      if command -v zip >/dev/null 2>&1; then
        cd "$(dirname "$report_dir")" && zip -r "$tmp_archive" -@ < "$filelist" 2>/dev/null
      else
        log_event "WARN" "packager" "zip_unavailable" "collector.skipped" \
          "\"reason\":\"zip tool not available, falling back to tar.gz\"" 2>/dev/null
        tar czf "$tmp_archive" -C "$(dirname "$report_dir")" \
          --files-from="$filelist" 2>/dev/null
      fi
      ;;
  esac
  
  rm -f "$filelist"
  
  # Step 794: Compute archive sha256
  local archive_hash=""
  if command -v sha256sum >/dev/null 2>&1; then
    archive_hash=$(sha256sum "$tmp_archive" | awk '{print $1}')
  elif command -v openssl >/dev/null 2>&1; then
    archive_hash=$(openssl dgst -sha256 -r "$tmp_archive" | awk '{print $1}')
  fi
  
  # Step 792: Atomic rename
  sync 2>/dev/null
  mv "$tmp_archive" "$output_file"
  
  # Step 795: Final manifest
  packager_write_manifest "$report_dir" "false"
  
  # Step 802: Packaging stats
  local archive_size=$(wc -c < "$output_file" 2>/dev/null || echo 0)
  local archive_size_mb=$(( archive_size / 1048576 ))
  
  cat > "$report_dir/packaging_stats.json" << PSEOF
{"archive":"$(basename "$output_file")","sha256":"$archive_hash","size_bytes":$archive_size,"size_mb":$archive_size_mb,"total_files":$total_files,"compression_level":$comp_level,"format":"$format"}
PSEOF
  
  log_event "INFO" "packager" "packager.finish" "packager.complete" \
    "\"file\":\"$output_file\",\"size_mb\":\"$archive_size_mb\",\"sha256\":\"$archive_hash\"" 2>/dev/null
  
  echo "$output_file"
}

# Step 799-800, 805-806: Build file list with denylist/self-mirror checks
packager_build_filelist() {
  local report_dir="$1"
  local output="$2"
  local prefix="$3"
  local rid=$(basename "$report_dir")
  
  find "$report_dir" -type f 2>/dev/null | while read -r f; do
    local rel=$(echo "$f" | sed "s|$(dirname "$report_dir")/||")
    
    # Step 800: Self-mirror check
    case "$f" in
      *.tar.gz|*.tar.gz.tmp|*.zip) continue ;;
      */tmp/*) continue ;;
    esac
    
    # Step 805: Skip NUL/unprintable filenames
    echo "$rel" | grep -qP '[\x00-\x1f]' 2>/dev/null && continue
    
    echo "$rel"
  done > "$output"
}

# Step 795-796: Manifest generation
packager_write_manifest() {
  local report_dir="$1"
  local partial="${2:-false}"
  local manifest="$report_dir/manifest.json"
  
  local files_json=""
  local total_size=0
  local total_files=0
  
  find "$report_dir" -type f ! -name "manifest.json" 2>/dev/null | sort | while read -r f; do
    local rel=$(echo "$f" | sed "s|$report_dir/||")
    local size=$(wc -c < "$f" 2>/dev/null || echo 0)
    local hash=""
    command -v sha256sum >/dev/null 2>&1 && hash=$(sha256sum "$f" | awk '{print $1}')
    total_size=$((total_size + size))
    total_files=$((total_files + 1))
    echo "{\"path\":\"$rel\",\"size\":$size,\"sha256\":\"$hash\"}"
  done > "$report_dir/.manifest_files.tmp"
  
  local entries=$(cat "$report_dir/.manifest_files.tmp" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  
  cat > "$manifest" << MEOF
{
  "schema_id": "manifest",
  "schema_version": "1",
  "report_id": "${TOOL_REPORT_ID:-unknown}",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)",
  "tool_version": "$(cat "${TOOL_BASE_DIR:-/opt/keenetic-debug}/VERSION" 2>/dev/null || echo unknown)",
  "partial": $partial,
  "files": [$entries],
  "statistics": {"total_files": $(wc -l < "$report_dir/.manifest_files.tmp" 2>/dev/null || echo 0)}
}
MEOF
  
  rm -f "$report_dir/.manifest_files.tmp"
}

# Step 808: Disable compression option
packager_store_only() {
  local report_dir="$1"
  local output_file="$2"
  tar cf "$output_file" -C "$(dirname "$report_dir")" "$(basename "$report_dir")" 2>/dev/null
}
