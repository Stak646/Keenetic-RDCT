# Plugin Contract — Полное описание контракта

## plugin.json

Полная JSON Schema: `schemas/plugin.schema.json`

### Обязательные поля
- `schema_id`: "plugin"
- `schema_version`: "1"
- `id`: стабильный ID (snake_case с точкой: `category.name`)
- `name`, `version` (SemVer), `contract_version` (int)
- `category`: system, network, wifi, vpn, storage, security, config, hooks, services, processes, scheduler, logs, telemetry, apps, mirror, api
- `supported_research_modes`: subset ["light","medium","full","extreme"]
- `supported_perf_modes`: subset ["lite","middle","hard","auto"]
- `requires_root`, `dangerous`: boolean
- `dependencies`: {commands:[], files:[], optional_fallbacks:{}}
- `estimated_cost`: {time_s, cpu_pct, ram_mb, io_mb}
- `timeout_s` (>0, ≤300), `max_output_mb` (>0, ≤200)
- `privacy_tags`: subset privacy_tag enum

### Опциональные поля
- `description_en`, `description_ru`
- `incremental`: {key, strategy, cursors}
- `depends_on`: [other collector IDs]

## result.json

Полная JSON Schema: `schemas/result.schema.json`

### Обязательные
- `schema_id`: "result", `schema_version`: "1"
- `collector_id`, `status` (OK/SKIP/SOFT_FAIL/HARD_FAIL/TIMEOUT)
- `metrics`: {output_size_bytes, commands_run, commands_failed}
- `artifacts`: array of relative paths
- `errors`: [{code, message}]

### Коды ошибок collectors (Step 594)
- `DEP_MISSING`: Зависимость не найдена
- `PERMISSION_DENIED`: Нет прав
- `TIMEOUT`: Превышен таймаут
- `OUTPUT_LIMIT`: Превышен размер выхода
- `INTERNAL_ERROR`: Внутренняя ошибка
- `DANGEROUS_DISABLED`: dangerous_ops=false
- `ROOT_REQUIRED`: Нет root

## Lifecycle

1. Framework creates workdir + input.json
2. Framework sources run.sh in subshell with env vars
3. Collector writes artifacts/ and result.json
4. Framework validates result.json, injects metadata
5. Framework computes artifact_index.json
6. RedactionEngine processes artifacts/ (post-processing)
7. Packager includes in snapshot

## Progress (Step 575)
Collector may optionally write `progress.json` with `{"percent": 50, "phase": "scanning"}`.
Framework reads it for WebUI progress display. If absent, progress is estimated by phase weights.

## Phase Barriers (Step 582)
Plan execution follows phases: system → network → apps → packaging.
`depends_on` field enables fine-grained ordering within phases.
`progress_weight` determines each collector's contribution to overall progress bar.

## Self-Test (Steps 610-611)
Collector may implement `run.sh --self-test` returning 0 if all dependencies are operational.
Preflight can call self-test to detect environment issues early and include results as recommendations.

## Artifact Index (Step 629)
CI verifies: `artifacts_index.json` matches actual files; no paths outside `collectors/<id>/`.
