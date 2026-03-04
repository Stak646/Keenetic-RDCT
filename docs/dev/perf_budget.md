# Performance Budget — Бюджет производительности

## Определение «тяжёлого» collector

Collector считается **heavy**, если:
- `estimated_cost.time_s > 30`
- `estimated_cost.cpu_pct > 30`
- `estimated_cost.ram_mb > 32`
- `estimated_cost.io_mb > 50`

Heavy collectors пропускаются первыми при перегрузке Governor.

## Лимиты по умолчанию

| Параметр | Значение | Описание |
|---|---|---|
| `timeout_s` | 60 (max 300) | Per-collector таймаут |
| `max_output_mb` | 50 (max 200) | Макс. размер выходных артефактов |
| `global_timeout_s` | 1800 (30 min) | Общий таймаут сессии |
| `max_snapshot_mb` | 500 | Макс. размер финального архива |

## Бюджет по mode

| | Lite | Middle | Hard | Auto |
|---|---|---|---|---|
| Max workers | 1 | 2 | CPU count | dynamic |
| CPU limit | 30% | 50% | 95% | dynamic |
| RAM reserve | 40% | 25% | 5% | dynamic |
| IO nice | idle | best-effort | none | dynamic |

## Правила

1. Каждый collector **обязан** иметь `estimated_cost` в plugin.json
2. Каждый collector **обязан** иметь `timeout_s > 0` и `max_output_mb > 0`
3. CI проверяет: все plugin.json содержат эти поля (не пустые)
4. Governor суммирует `estimated_cost` при составлении plan
5. При превышении бюджета — SKIP heavy collectors с причиной `governor_budget`
