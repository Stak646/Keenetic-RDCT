#!/bin/sh
set -eu

# RDCT installer (local, MVP)
# Usage:
#   RDCT_BASE=/tmp/mnt/sda1/rdct sh install.sh
# If RDCT_BASE is not set, tries to auto-detect a USB mount and uses <mount>/rdct.

detect_usb_mount() {
  # Heuristic: /dev/sd* or /dev/mmcblk* in /proc/mounts, non-virtual fs
  awk '
    $3 !~ /^(proc|sysfs|tmpfs|devtmpfs|overlay|squashfs|ramfs)$/ {
      if ($1 ~ /^\/dev\/(sd[a-z][0-9]*|mmcblk[0-9]+p?[0-9]*|nvme[0-9]+n[0-9]+p?[0-9]*)$/) {
        print $2;
        exit 0;
      }
    }' /proc/mounts 2>/dev/null || true
}

BASE="${RDCT_BASE:-}"
if [ -z "$BASE" ]; then
  MP="$(detect_usb_mount)"
  if [ -z "$MP" ]; then
    echo "ERROR: USB mount not detected. Set RDCT_BASE to a path on USB (e.g. /tmp/mnt/sda1/rdct)." >&2
    exit 2
  fi
  BASE="${MP}/rdct"
fi

mkdir -p "$BASE"
mkdir -p "$BASE/config" "$BASE/deps" "$BASE/cache" "$BASE/run" "$BASE/reports" "$BASE/logs"

echo "RDCT base path: $BASE"

# Create config if missing
if [ ! -f "$BASE/config/rdct.json" ]; then
  echo "Creating default config..."
  python3 -m rdct --base "$BASE" init || true
fi

echo "Done."
echo "Next:"
echo "  python3 -m rdct --base "$BASE" preflight"
echo "  python3 -m rdct --base "$BASE" run --mode light"
echo "  python3 -m rdct --base "$BASE" serve --bind 0.0.0.0 --port 8080"
