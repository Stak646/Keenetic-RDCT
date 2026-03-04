# Architecture / Архитектура

## Обзор

```
┌──────────────────────────────────────────────────┐
│                   CLI / WebUI                     │
├──────────────────────────────────────────────────┤
│                     Core                          │
│  ┌──────────┐  ┌──────────┐  ┌────────────────┐  │
│  │ Preflight│→ │Orchestr. │→ │   Packager     │  │
│  └──────────┘  └────┬─────┘  └───────┬────────┘  │
│                     │                │            │
│  ┌──────────┐  ┌────▼─────┐  ┌───────▼────────┐  │
│  │ Governor │← │Collectors│→ │  Manifest      │  │
│  │(resource)│  │ Manager  │  │  Builder       │  │
│  └──────────┘  └────┬─────┘  └────────────────┘  │
│                     │                             │
│  ┌──────────────────▼──────────────────────────┐  │
│  │           Collectors (plugins)              │  │
│  │  system│network│wifi│vpn│storage│security│…  │  │
│  └─────────────────┬───────────────────────────┘  │
│                    │                              │
│  ┌─────────┐  ┌────▼────┐  ┌──────────────────┐  │
│  │Redaction│← │Inventory│→ │  ChecksEngine    │  │
│  │ Engine  │  │ Builder │  │  (baseline/delta) │  │
│  └─────────┘  └─────────┘  └──────────────────┘  │
│                                                   │
│  ┌──────────┐  ┌──────────┐  ┌────────────────┐  │
│  │ StateDB  │  │ Adapters │  │  AppManager    │  │
│  │(delta/   │  │(ndm/rci) │  │               │  │
│  │ chain)   │  └──────────┘  └────────────────┘  │
│  └──────────┘                                     │
├──────────────────────────────────────────────────┤
│  Installer │ Configurator │ Debugger │ Updater   │
└──────────────────────────────────────────────────┘
```

## Поток данных

1. **CLI/WebUI** → Core: запрос snapshot (режим, параметры)
2. **Core → Preflight**: capability detect + StateDB hints → plan.json
3. **Core → Governor**: запрос ресурсного бюджета
4. **Core → CollectorsManager**: выполнение plan по очереди/параллельно
5. **CollectorsManager → Collector**: запуск в отдельном процессе
6. **Collector → result.json + artifacts/**: структурированный результат
7. **CollectorsManager → InventoryBuilder**: корреляции
8. **CollectorsManager → RedactionEngine**: маскирование (Light/Medium)
9. **InventoryBuilder → ChecksEngine**: проверки baseline vs delta
10. **Packager**: потоковая упаковка + manifest + sha256
11. **Core → CLI/WebUI**: прогресс + итоговый отчёт

## Жизненный цикл

```
install → first-run → preflight → plan → execute collectors
    → build inventory/checks → redact → package snapshot → report
```

## Детальное проектирование

| Документ | Покрывает |
|---|---|
| [MODULE_MAP.md](MODULE_MAP.md) | Карта модулей, точки входа, IPC |
| [DESIGN_CORE.md](DESIGN_CORE.md) | Runtime-структура, lifecycle, report_id, StateDB, plan, throttling, collector contract |
| [DESIGN_COLLECTORS.md](DESIGN_COLLECTORS.md) | Каталог collectors, команды/fallback, зеркалирование, excluded.json, redaction |
| [DESIGN_WEBUI_CLI.md](DESIGN_WEBUI_CLI.md) | WebUI/API, security, CLI, AppManager, Packager, ENOSPC/OOM, профилирование, релизы |
| [DATA_CONTRACTS.md](DATA_CONTRACTS.md) | Форматы артефактов |
| [SECURITY_MODEL.md](SECURITY_MODEL.md) | Модель безопасности |
