# Security & Privacy Notes (MVP)

- RDCT is designed to be **USB-only**: it refuses to run if base path is not on an external mount.
- RDCT does **not** send collected data anywhere.
- WebUI/API serves locally. API requires a token (see `config/rdct.json`).
- In Light/Medium modes the tool applies **best-effort redaction** of command outputs and config exports.
- `SensitiveScannerCollector` produces a redacted sensitive report and a redaction plan for exports.

Before sharing reports, review `reports/top_findings.json` and `security/sensitive_findings.json`.
