# Incremental Snapshots & Chain

## How It Works

1. **Baseline**: Full collection (chain_depth=0). All collectors run, all data captured.
2. **Delta**: Incremental collection. Only changed data captured, using StateDB hints.
3. **Chain**: Sequence of baseline + deltas. `chain_max_depth` limits depth (default: 10).

## StateDB
- SQLite (WAL mode) when available, JSON fallback otherwise
- Stores: file index, command fingerprints, log cursors, inventory state, chain metadata, collector status
- Device fingerprint ensures DB matches the device

## Rebase
Merge deltas into new baseline when chain is deep or large:
```shell
keenetic-debug chain rebase    # Requires dangerous_ops=true
```

## Compaction
Remove old deltas while preserving chain integrity:
```shell
keenetic-debug chain compact   # Requires dangerous_ops=true
```

## Checks
ChecksEngine compares baseline vs current: new ports, package drift, config changes, WiFi/VPN regression, storage growth, log anomalies.

## Reading checks.json
Each check has: `id`, `severity` (INFO/WARN/CRIT), `title`, `description`, `evidence`, `remediation_hint`, `privacy_tags`, `category`.
