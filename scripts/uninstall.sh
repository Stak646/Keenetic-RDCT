#!/bin/sh
# keenetic-debug uninstall — Step 407
# Delegates to install.sh --uninstall
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/install.sh" --uninstall "$@"
