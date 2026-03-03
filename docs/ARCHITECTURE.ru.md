# Архитектура (MVP)

RDCT устроен так:

- **CLI** (`rdct/cli.py`): init, preflight, run, serve
- **Оркестратор** (`rdct/core.py`): жизненный цикл запуска, фазы, манифесты, архивы
- **Коллекторы** (`rdct/collectors/*`): подключаемые модули сбора данных
- **Инкрементальный движок** (`rdct/incremental/*`): baseline/delta и diff‑отчёт
- **Policy Engine** (`rdct/policy/*`): адаптивные триггеры → план действий
- **WebUI/API** (`rdct/web/server.py` + `rdct/web/static/*`): локальный UI и API (token)

## Жёсткий режим USB-only

Preflight читает `/proc/mounts` и отказывается работать, если базовый путь не находится на внешнем носителе
(эвристики для `/dev/sd*`, `/dev/mmcblk*` и т.п.).

Все артефакты пишутся только в:

- `deps/`
- `cache/`
- `run/`
- `reports/`
- `logs/`

Запись во внутреннюю память не предполагается (где возможно, временные файлы также направляются в `logs/tmp`).

## Фазы

1. Фаза 1: обязательные коллекторы (device/env/storage/proc/dmesg/network/opkg и т.п.)
2. Оценка политики → `snapshot/adaptive/plan.json`
3. Фаза 2: опциональные коллекторы (web discovery, sensitive scan, mirror)
4. Фаза 3: diff‑отчёт (baseline vs текущий)
5. Фаза 4: summary + checksums
6. Манифест + архив

## Расширяемость

- Добавить коллектор: реализуйте `BaseCollector.run()` и зарегистрируйте в `collectors/__init__.py`
- Добавить правило: обновите `policy/rules.json` и/или расширьте маппинг условий/действий в `policy/engine.py`
