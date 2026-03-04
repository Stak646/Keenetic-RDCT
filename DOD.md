# Definition of Done

## Обязательные файлы в snapshot
- [x] manifest.json (sha256 для каждого файла)
- [x] preflight.json (capabilities, warnings, estimates)
- [x] plan.json (tasks с reason)
- [x] summary.json (collector stats, overall status)
- [x] event_log.jsonl (structured events)
- [x] debugger_report.json (при любом завершении)
- [x] redaction_report.json (всегда, даже в Full)
- [x] inventory.json (port→PID→package→config→endpoint)
- [x] checks.json (diff-driven аномалии)
- [x] device.json (fingerprint, model, arch)

## Безопасность
- [x] bind=127.0.0.1 по умолчанию
- [x] Bearer token auth
- [x] Роли readonly/admin
- [x] dangerous_ops=false по умолчанию
- [x] Rate limiting
- [x] CSRF Origin check
- [x] Нет 0.0.0.0 в дефолтах (CI проверка)
- [x] Redaction в Light/Medium
- [x] Sanitize export

## Надёжность
- [x] ENOSPC → partial snapshot + debugger report
- [x] OOM → Governor throttle + skip heavy
- [x] Watchdog → global timeout
- [x] Fault isolation → collector crash не роняет run
- [x] Atomic publish → tmp+rename+fsync
- [x] Self-mirror → CRITICAL stop

## Инкремент
- [x] StateDB (SQLite WAL / JSON fallback)
- [x] Device fingerprint check
- [x] Smart plan from state
- [x] Chain: baseline→delta, rebase, compact
- [x] ChecksEngine: 10+ категорий проверок

## Документация
- [x] RU/EN зеркальная структура
- [x] Quick Start, Installation, WebUI, CLI, Config, Architecture, Security, Troubleshooting, Plugin Guide
- [x] 112+ i18n ключей × 2 языка

## CI
- [x] Schema validation
- [x] L10n coverage
- [x] Safe defaults check
- [x] UTF-8 check
- [x] Collector validation
- [x] Docs parity
- [x] Sandbox smoke tests
