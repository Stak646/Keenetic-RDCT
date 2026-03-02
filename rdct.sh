#!/bin/sh
# Simple wrapper to run RDCT
# Usage: ./rdct.sh --base /tmp/mnt/sda1/rdct run --mode light
PY="${PYTHON:-python3}"
exec "$PY" -m rdct.cli "$@"
