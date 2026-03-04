# MODULE_MAP.md — Карта модулей и точки входа

> Шаги 53–54 плана. Какие модули — исполняемые компоненты, какие — библиотеки.

## 1. Точки входа продукта (Step 54)

| Точка входа | Тип | Описание |
|---|---|---|
| `install.sh` | Shell-скрипт | Установка одной командой (curl/wget pipe) |
| `bin/keenetic-debug` | Shell-скрипт | CLI: `tool start`, `tool report list`, … |
| `modules/webui_server.sh` (+ Python) | Сервис | HTTP API + статический фронтенд, автозапуск |
| `modules/core.sh` | Библиотека (source) | Оркестратор: plan → execute → package |
| Sandbox mode | Флаг `--sandbox` | Использует фикстуры вместо реальных команд |
| USB-only mode | Флаг `--usb-only` / config | Отказ старта без USB |

## 2. Классификация модулей (Step 53)

### 2.1. Исполняемые компоненты (отдельные процессы)

| Модуль | Runtime | Описание |
|---|---|---|
| **CLI** (`bin/keenetic-debug`) | ash | Точка входа пользователя, парсит команды |
| **WebUI Server** | Python (≥3.8) | HTTP API + static SPA, слушает порт |
| **Collector** (каждый) | ash / Python | Отдельный процесс на каждый сборщик |

### 2.2. Библиотеки (source / import)

| Модуль | Runtime | Файлы | Описание |
|---|---|---|---|
| **Core** | ash | `modules/core.sh` | Оркестрация, очередь задач, state, cancel |
| **Preflight** | ash | `modules/preflight.sh` | Capability detect, plan, cost estimate |
| **Governor** | ash | `modules/governor.sh` | CPU/RAM/IO мониторинг, throttling |
| **CollectorsManager** | ash | `modules/collectors_manager.sh` | Реестр, зависимости, приоритеты, dispatch |
| **Configurator** | ash | `modules/configurator.sh` | Чтение/валидация config.json, миграции |
| **Packager** | ash | `modules/packager.sh` | Потоковое создание tar.gz + sha256 |
| **RedactionEngine** | ash | `modules/redaction.sh` | Маскирование/zeroize по privacy policy |
| **InventoryBuilder** | ash | `modules/inventory.sh` | Корреляция port→pid→pkg→config→endpoint |
| **ChecksEngine** | ash | `modules/checks.sh` | Diff-driven проверки baseline vs delta |
| **DeltaManager** | ash | `modules/delta_manager.sh` | StateDB API, chain, rebase/compaction |
| **AppManager** | ash | `modules/app_manager.sh` | init.d, статус, backup/restore |
| **Adapters** | ash | `modules/adapters.sh` | ndm/rcicli/http_rci + fallback |
| **Debugger** | ash | `modules/debugger.sh` | Аварийный отчёт, trap-handler |
| **UpdateManager** | ash | `modules/update_manager.sh` | Обновление + pinned hashes + rollback |
| **i18n** | ash | `modules/i18n.sh` | Загрузка ru.json/en.json, gettext-подобный API |
| **Logger** | ash | `modules/logger.sh` | JSONL event log + human-readable |

### 2.3. Принципы разделения

- **Правило**: если модуль может заблокировать основной процесс или может упасть — он запускается как **отдельный процесс** с таймаутом.
- **Collectors** всегда запускаются в дочерних процессах (`modules/collectors_manager.sh` вызывает каждый через `timeout`).
- **WebUI Server** — единственный долгоживущий процесс (демон).
- Все остальные модули — функции, которые загружаются через `. modules/xxx.sh` в runtime Core.

## 3. Граф зависимостей модулей

```
CLI ──→ Core ──→ Configurator
                  ├── Preflight ──→ Governor
                  │                  ├── CollectorsManager ──→ Collector[N]
                  │                  └── DeltaManager (StateDB)
                  ├── InventoryBuilder
                  ├── ChecksEngine
                  ├── RedactionEngine
                  ├── Packager
                  ├── Debugger (trap)
                  └── Logger / i18n

WebUI Server ──→ Core (API вызовы через IPC/файлы)
                  ├── AppManager
                  └── Adapters
```

## 4. IPC между WebUI и Core

WebUI Server **не вызывает Core напрямую**. Взаимодействие через файловую систему:

| Механизм | Направление | Файлы |
|---|---|---|
| Команда запуска | WebUI → Core | `run/command.json` (start/stop/cancel) |
| Статус прогресса | Core → WebUI | `run/progress.json` (обновляется каждые N сек) |
| Результат | Core → WebUI | `var/reports/<id>/manifest.json` |
| Порт WebUI | WebUI → все | `run/webui.port` |
| PID WebUI | WebUI → CLI | `run/webui.pid` |
