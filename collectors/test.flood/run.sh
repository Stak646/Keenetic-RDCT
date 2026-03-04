#!/bin/sh
mkdir -p "$COLLECTOR_WORKDIR/artifacts"
dd if=/dev/zero of="$COLLECTOR_WORKDIR/artifacts/big.bin" bs=1M count=100 2>/dev/null
