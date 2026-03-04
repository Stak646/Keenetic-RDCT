# Snapshot Format

## Archive Structure

```
<report_id>.tar.gz
└── <report_id>/
    ├── manifest.json          # File index with sha256
    ├── preflight.json         # Environment capabilities
    ├── plan.json              # Execution plan
    ├── summary.json           # Run summary with stats
    ├── event_log.jsonl        # Structured event log
    ├── debugger_report.json   # Debugging info
    ├── redaction_report.json  # Redaction actions
    ├── inventory.json         # Port→PID→Package map
    ├── effective_config.json  # Config used (redacted)
    ├── device.json            # Device info
    ├── packaging_stats.json   # Archive statistics
    ├── collectors/
    │   ├── system.base/
    │   │   ├── result.json
    │   │   ├── artifacts/
    │   │   └── artifacts_index.json
    │   ├── network.base/
    │   └── ...
    └── logs/
        └── checkpoints.jsonl
```

## Key Files

- **manifest.json**: Source of truth. Contains path, size, sha256 for every file.
- **redaction_report.json**: What was found and masked (Light/Medium) or flagged (Full/Extreme).
- **inventory.json**: Correlation map: listening port → process → package → config → endpoints.
- **summary.json**: Overall status (OK/PARTIAL/FAILED), collector counts, modes.
