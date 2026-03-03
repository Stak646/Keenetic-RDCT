# Privacy & Redaction

RDCT collects diagnostics from a router. These snapshots may contain sensitive data.

## USB-only

RDCT refuses to run unless the base directory is on an external USB mount.

## Redaction levels

Redaction is applied during collection (where possible) and during export.

- `strict` — mask secrets, cookies, tokens; stub large/binary/sensitive files
- `normal` — mask common secrets; keep more text intact
- `off` — no redaction (NOT recommended for sharing)

## Safe view

WebUI is intended for local access. Use **Export** with redaction before sharing the bundle.

## What RDCT will NOT do

- No credential submission (no login attempts)
- No outbound traffic by default (network policy defaults to `external_traffic_allowed=false`)
- No auto-start of third-party services

## Recommendations

- Prefer `light` or `medium` when you only need quick triage
- For support bundles, always use `export --level strict`
