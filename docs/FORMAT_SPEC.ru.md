# Формат снапшота (MVP)

Корень снапшота содержит:

- `manifest.json` — точка входа
- `meta/run_context.json` (или `logs/tool/run_context.json` в новых сборках)
- `logs/collectors/<collector_id>/result.json`
- `reports/top_findings.json`
- `reports/recommendations.json`
- `diff/diff_report.json` (если существует baseline)
- `checksums.sha256`

## Минимальная схема result.json коллектора

Каждый коллектор пишет `logs/collectors/<id>/result.json`:

- `collector` (name/version/id)
- `run` (run_id/status/duration)
- `scope` (modes, redaction, root)
- `stats` (items/files/bytes)
- `artifacts[]` (relative path, type, флаги sensitive/redacted)
- `findings[]` (severity/code/title/details/refs)
- `normalized_data` (опционально) — используется для incremental diff

## Diff‑отчёт

`diff/diff_report.json` содержит секции:

- packages
- processes
- ports
- network
- configs
- logs

Diff‑отчёт является «redaction-safe»: без секретных значений, только подписи/хэши/сигнатуры.
