# Snapshot Format (MVP)

Snapshot root contains:

- `manifest.json` – entrypoint
- `meta/run_context.json`
- `logs/collectors/<collector_id>/result.json`
- `reports/top_findings.json`
- `reports/recommendations.json`
- `diff/diff_report.json` (if baseline exists)
- `checksums.sha256`

## Collector result schema (minimum)

Each collector writes `logs/collectors/<id>/result.json` with:

- `collector` (name/version/id)
- `run` (run_id/status/duration)
- `scope` (modes, redaction, root)
- `stats` (items/files/bytes)
- `artifacts[]` (relative path, type, sensitive/redacted flags)
- `findings[]` (severity/code/title/details/refs)
- `normalized_data` (optional) – used by incremental diff

## Diff report

`diff/diff_report.json` includes sections:

- packages
- processes
- ports
- network
- configs
- logs (placeholder)

The report is redaction-safe (no secret values, only hashes/signatures).
