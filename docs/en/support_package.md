# Support Package

## Quick Collect
```shell
keenetic-debug start --mode light --perf lite
keenetic-debug sanitize <report_id>
```

## What to Send
Send the sanitized archive. Support will look at:
1. `summary.json` — overall status and modes
2. `checks.json` — detected anomalies
3. `inventory.json` — port/process/package map
4. `redaction_report.json` — what was masked
5. `debugger_report.json` — if errors occurred
6. `preflight.json` — environment capabilities
