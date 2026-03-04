# JSON Schema Registry — keenetic-debug

Все артефакты проекта валидируются по JSON Schema 2020-12.

## Реестр схем (15 шт.)

| Schema ID | Файл | Описание |
|---|---|---|
| `plugin` | plugin.schema.json | Метаданные collector'а |
| `result` | result.schema.json | Результат выполнения collector'а |
| `manifest` | manifest.schema.json | Описатель snapshot'а |
| `event_log_entry` | event_log_entry.schema.json | Запись event log (JSONL) |
| `audit_event` | audit_event.schema.json | Запись audit log (JSONL) |
| `preflight` | preflight.schema.json | Результат preflight |
| `plan` | plan.schema.json | План выполнения |
| `checks` | checks.schema.json | Diff-driven проверки |
| `redaction_report` | redaction_report.schema.json | Отчёт о редактировании |
| `excluded` | excluded.schema.json | Пропущенные пути |
| `inventory` | inventory.schema.json | Инвентаризация |
| `inventory_delta` | inventory_delta.schema.json | Дельта inventory |
| `config` | config.schema.json | Конфигурация |
| `state` | state.schema.json | StateDB JSON fallback |
| `sbom` | sbom.schema.json | Software BOM |

Дополнительно:
- `common_defs.schema.json` — общие определения ($defs): timestamp, report_id, status, severity, privacy_tags, estimated_cost, safe_path, arch
- `registry.json` — машиночитаемый реестр (schema_id → файл)

## Правила совместимости (Step 257, 259)

- Каждый артефакт содержит `schema_id` и `schema_version`
- Core vX **обязан** читать `schema_version` в диапазоне `[X-1 … X]`
- Если `schema_version < X-1` → `SKIP` + рекомендация обновления
- Несовместимый `contract_version` в plugin.json → SKIP collector (Step 258)
- **Добавление** optional полей с дефолтами — без bump major version
- **Удаление/переименование** обязательных полей — только через major bump schema_version

## Общие определения (Step 260-261)

`common_defs.schema.json` содержит:
- `status`: OK / SKIP / SOFT_FAIL / HARD_FAIL / TIMEOUT — единый enum
- `severity`: INFO / WARN / CRIT
- `privacy_tag`: password / token / ip / mac / ssid / cookie / key / cert / logs / payload
- `report_id`: regex pattern `^[a-z0-9]+-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{4}$` (Step 262)
- `safe_path`: без нулевых байтов и непечатных символов (Step 263)
- `estimated_cost`: cpu_pct / ram_mb / io_mb / net_kb / time_s

## Валидация

```bash
# CI — все примеры vs схемы
make schemas

# Тесты (positive + negative)
tests/schemas/run_schema_tests.sh

# Runtime — перед публикацией snapshot
scripts/validate_runtime.sh <workdir>
```

## Тест совместимости (Step 270)

Старые примеры (version X-1) сохраняются в `tests/golden/` и валидируются текущими схемами при каждом CI-прогоне.
