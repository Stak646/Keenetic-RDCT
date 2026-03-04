# Data Contracts / Контракты данных

## Принципы

1. Все артефакты — JSON, валидируемые JSON Schema 2020-12
2. Каждый файл содержит `schema_id` и `schema_version`
3. Совместимость: Core vX читает schema_version [X-1 … X]
4. При несовместимости — SKIP + рекомендация обновления

## Артефакты snapshot

| Артефакт | schema_id | Описание |
|----------|-----------|----------|
| manifest.json | keenetic-debug.manifest | Список файлов, sha256, статистика |
| preflight.json | keenetic-debug.preflight | Проверки среды, capability, план |
| inventory.json | keenetic-debug.inventory | Корреляции порт→процесс→пакет→конфиг |
| checks.json | keenetic-debug.checks | Результаты проверок |
| redaction_report.json | keenetic-debug.redaction_report | Что замаскировано и по какому правилу |
| event_log.jsonl | keenetic-debug.event_log_entry | Лог событий (построчно) |
| debugger_report.json | keenetic-debug.debugger_report | Аварийный отчёт |
| collectors/*/result.json | keenetic-debug.collector.result | Результат коллектора |
| collectors/*/plugin.json | keenetic-debug.collector.plugin | Метаданные коллектора |

## Collector контракт

Каждый collector — отдельный процесс. На входе — env vars, на выходе:
- `result.json` — обязательно (статус + данные)
- `artifacts/` — опционально (файлы)
- `logs/collector.log` — опционально

Статусы: `OK` | `SKIP` | `SOFT_FAIL` | `HARD_FAIL` | `TIMEOUT`
