# DESIGN_CORE.md — Проектирование ядра, жизненный цикл, форматы

> Шаги 55–70 плана.

---

## 1. Runtime-директория (Step 55)

После установки на роутере:

```
/opt/keenetic-debug/
├── bin/                    # Точки входа CLI
│   └── keenetic-debug      # → ../modules/cli.sh
├── modules/                # Библиотеки Shell (source)
│   ├── core.sh
│   ├── preflight.sh
│   ├── governor.sh
│   ├── collectors_manager.sh
│   ├── configurator.sh
│   ├── packager.sh
│   ├── redaction.sh
│   ├── inventory.sh
│   ├── checks.sh
│   ├── delta_manager.sh
│   ├── app_manager.sh
│   ├── adapters.sh
│   ├── debugger.sh
│   ├── update_manager.sh
│   ├── i18n.sh
│   └── logger.sh
├── collectors/             # Плагины-сборщики
│   ├── system.base/
│   ├── network.base/
│   └── ...
├── web/                    # WebUI (Python HTTP server + static SPA)
│   ├── server.py
│   └── static/
├── schemas/                # JSON Schema 2020-12
├── i18n/                   # ru.json, en.json
├── policies/               # denylist.json, privacy.json
├── docs/                   # Offline-копия документации
├── scripts/                # Вспомогательные утилиты
├── run/                    # Runtime state (pid, port, locks)
│   ├── webui.pid
│   ├── webui.port
│   ├── command.json
│   └── progress.json
├── var/                    # Данные (persistent)
│   ├── state.db            # StateDB (SQLite или JSON fallback)
│   ├── reports/            # Готовые snapshot'ы
│   │   └── <report_id>/
│   ├── audit.log           # Append-only audit
│   └── backups/            # Backup'ы AppManager
├── tmp/                    # Временные файлы (workdir)
│   └── <session_id>/       # Изолированная рабочая директория сессии
├── config.json             # Конфигурация пользователя
└── version.json            # Версия + schema_compat
```

**Правила**:
- `run/` — ephemeral, очищается при старте
- `var/` — persistent, не удалять при upgrade
- `tmp/` — ephemeral, очищается при старте и завершении
- Всё в пределах `/opt/keenetic-debug/` (single-directory deployment)

---

## 2. Жизненный цикл запуска (Step 56)

```
install.sh
   │
   ▼
first-run (генерация token, config defaults)
   │
   ▼
CLI: tool start [--mode X] [--perf Y] [--baseline|--incremental]
   │
   ▼
┌─ preflight ────────────────────────────────────┐
│  1. Загрузить config.json + валидация          │
│  2. Capability detect (команды/файлы/Entware)  │
│  3. Проверить носитель, свободное место        │
│  4. Если incremental — загрузить StateDB       │
│  5. Составить план (plan.json)                 │
│  6. Оценить стоимость (time/size/cpu/ram/io)   │
│  7. Выпустить preflight.json                   │
└────────────────────────────────────────────────┘
   │
   ▼
┌─ execute ──────────────────────────────────────┐
│  1. Инициализировать Governor (CPU/RAM лимиты) │
│  2. Запустить event log (JSONL)                │
│  3. Для каждого collector из plan.json:        │
│     a. Проверить зависимости (capability)      │
│     b. Выделить workdir (tmp/<session>/coll/)  │
│     c. Запустить в отдельном процессе          │
│     d. Ограничить timeout + max_output_mb      │
│     e. Забрать result.json + artifacts         │
│     f. Записать чекпоинт                       │
│     g. Governor: проверить нагрузку, throttle  │
│  4. При cancel/timeout — graceful stop         │
└────────────────────────────────────────────────┘
   │
   ▼
┌─ post-processing ──────────────────────────────┐
│  1. InventoryBuilder → inventory.json          │
│  2. ChecksEngine → checks.json (если delta)    │
│  3. RedactionEngine → redact + report          │
│  4. Debugger → debugger_report.json            │
└────────────────────────────────────────────────┘
   │
   ▼
┌─ package ──────────────────────────────────────┐
│  1. Packager: потоковое создание tar.gz        │
│  2. sha256 на лету для каждого файла           │
│  3. Сформировать manifest.json                 │
│  4. temp → fsync → rename (атомарно)           │
│  5. Обновить StateDB (если baseline/incr)      │
└────────────────────────────────────────────────┘
   │
   ▼
┌─ publish ──────────────────────────────────────┐
│  1. Переместить в var/reports/<report_id>/      │
│  2. Audit log: записать событие                │
│  3. WebUI: обновить progress → DONE            │
│  4. CLI: вывести сводку + URL для скачивания   │
└────────────────────────────────────────────────┘
```

### Диаграмма состояний (Step 104)

```
                 ┌──────────┐
       start ──▶ │ PREFLIGHT│
                 └────┬─────┘
                      │ plan ready
                      ▼
                 ┌──────────┐   cancel    ┌───────────┐
                 │ RUNNING  │────────────▶│ CANCELLING│
                 └────┬─────┘             └─────┬─────┘
                      │                         │
              done/   │                         │ cleanup done
              error   │                         │
                      ▼                         ▼
                 ┌──────────┐             ┌───────────┐
                 │ PACKAGING│             │ CANCELLED │
                 └────┬─────┘             └───────────┘
                      │
                      ▼
                 ┌──────────┐
                 │   DONE   │
                 └──────────┘
                      │
              error   │
                      ▼
                 ┌──────────┐
                 │  FAILED  │  (partial snapshot saved)
                 └──────────┘

 Из любого состояния при crash:
                 ┌──────────┐
                 │ CRASHED  │  (Debugger report generated)
                 └──────────┘

 Resume из FAILED/CRASHED:
   tool start --resume → загрузка чекпоинта → RUNNING (с места остановки)
```

---

## 3. Формат report_id (Step 57)

```
<device_prefix>-<timestamp>-<random_suffix>

Пример: kn3010-20260304T143022Z-a7f3
```

| Компонент | Формат | Описание |
|---|---|---|
| `device_prefix` | `[a-z0-9]{2,16}` | Из модели устройства, lowercase, без спецсимволов. Пример: `kn3010`, `peak`, `ultra` |
| `timestamp` | `YYYYMMDDTHHmmSSZ` | ISO 8601 compact UTC |
| `random_suffix` | `[a-f0-9]{4}` | 4 hex символа (16 бит энтропии) для коллизий |

**Свойства**:
- Детерминированный префикс → snapshot'ы одного устройства группируются при сортировке
- Нет утечки идентификаторов (модель — публичная информация)
- Длина: 24–38 символов — допустимо для файловых имён

---

## 4. Device Fingerprint (Step 58)

Уникальный отпечаток устройства для привязки StateDB.

```json
{
  "model": "KN-3010",
  "os_version": "4.1.3",
  "arch": "mipsel",
  "unique_id": "<serial_or_uuid_if_available>",
  "mac_hash": "<sha256_of_primary_mac_first_8_chars>",
  "fingerprint": "<sha256_of_above_fields_concatenated>"
}
```

**Политика по режимам**:
- **Light/Medium**: `unique_id` — redacted (пустая строка), `mac_hash` — хешировано (sha256, первые 8 символов)
- **Full/Extreme**: `unique_id` и MAC в открытом виде (если доступны)

**Использование**: StateDB сверяет `fingerprint` при загрузке. Несовпадение → предупреждение + новый baseline.

---

## 5. StateDB (Steps 59–62)

### 5.1. Расположение (Step 59)

```
var/state.db          # Основное хранилище
var/state.db.bak      # Backup (перед rebase/compaction)
```

Формат: **SQLite WAL** (если python3+sqlite3 доступен) → **JSON fallback** (`var/state.json`).

Политика backup: автоматически перед каждым rebase/compaction. Хранить 1 предыдущую копию.

### 5.2. Схема StateDB

```sql
-- Индекс файлов (для зеркалирования и инкремента)
CREATE TABLE file_index (
  path         TEXT PRIMARY KEY,
  size         INTEGER,
  mtime        INTEGER,
  mode         TEXT,
  content_hash TEXT,       -- sha256, optional (heavy files — partial)
  last_seen    TEXT        -- ISO 8601
);

-- Отпечатки команд (для diff командных снимков)
CREATE TABLE command_fingerprints (
  command_id      TEXT PRIMARY KEY,
  normalized_hash TEXT,      -- sha256 нормализованного вывода
  last_ts         TEXT
);

-- Курсоры логов
CREATE TABLE log_cursors (
  log_id        TEXT PRIMARY KEY,
  inode         INTEGER,
  offset        INTEGER,
  last_ts       TEXT,
  rotation_hint TEXT         -- none | rotated | truncated
);

-- Inventory fingerprint
CREATE TABLE inventory_state (
  key   TEXT PRIMARY KEY,    -- 'ports', 'processes', 'services', 'packages'
  hash  TEXT,
  count INTEGER,
  last_ts TEXT
);

-- Метрики для профилирования
CREATE TABLE run_metrics (
  report_id     TEXT,
  collector_id  TEXT,
  duration_ms   INTEGER,
  cpu_pct_est   REAL,
  io_mb         REAL,
  output_mb     REAL,
  status        TEXT,
  PRIMARY KEY (report_id, collector_id)
);

-- Метаданные цепочки
CREATE TABLE chain_meta (
  report_id       TEXT PRIMARY KEY,
  snapshot_type   TEXT,        -- baseline | delta
  base_report_id  TEXT,
  chain_depth     INTEGER,
  created_at      TEXT,
  device_fingerprint TEXT
);
```

### 5.3. Baseline Mode (Step 60)

1. Запустить **все** collectors по выбранному профилю (research+perf mode)
2. Записать **полный** file_index, command_fingerprints, log_cursors, inventory_state
3. chain_meta: `snapshot_type=baseline`, `chain_depth=0`
4. Сохранить report_id как «текущая база»

### 5.4. Incremental Mode (Step 61)

1. Загрузить StateDB → определить base_report_id
2. Preflight: «умный план» — сравнить текущее состояние с StateDB
3. Запустить **только релевантные** collectors → delta-артефакты
4. ChecksEngine: сравнить inventory/configs/network с baseline
5. chain_meta: `snapshot_type=delta`, `chain_depth=parent.chain_depth+1`

### 5.5. Политика цепочки дельт (Step 62)

| Параметр | По умолчанию | Описание |
|---|---|---|
| `chain_max_depth` | 10 | Макс. глубина дельт до auto-rebase |
| `rebase_policy` | `every_n_deltas` | Когда перестраивать baseline |
| `rebase_n` | 10 | Каждые N дельт |
| `rebase_size_mb` | 100 | Или при total delta > N MB |

**Rebase**: CLI `tool chain rebase` / WebUI кнопка / auto при превышении.
**Compaction**: слияние мелких дельт в одну (опционально, не MVP).

---

## 6. Умный план — Preflight (Steps 63–65)

### 6.1. Алгоритм (Step 63)

```
INPUT:  config (modes), capabilities (detected commands/files), StateDB (if incremental)
OUTPUT: plan.json

1. Загрузить реестр всех collectors (collectors/*/plugin.json)
2. Отфильтровать по research_mode и perf_mode
3. Для каждого collector:
   a. Проверить dependencies (commands/files/endpoints)
   b. Если incremental и StateDB доступна:
      - Проверить, изменился ли «ключ» collector (file mtime, command hash, etc.)
      - Если нет изменений и strategy != none → SKIP с причиной "no_changes"
   c. Если requires_root и нет root → SKIP с причиной "no_root"
   d. Если dangerous и dangerous_ops=false → SKIP с причиной "dangerous_disabled"
   e. Иначе → INCLUDE с причиной включения
4. Упорядочить по зависимостям (topological sort)
5. Рассчитать estimated_total (time/size/cpu/ram)
6. Применить Governor бюджет: если перебор → SKIP heavy collectors
```

### 6.2. Структура preflight.json (Step 64)

```json
{
  "schema_id": "preflight",
  "schema_version": "1",
  "report_id": "kn3010-20260304T143022Z-a7f3",
  "timestamp": "2026-03-04T14:30:22Z",
  "device": {
    "model": "KN-3010",
    "arch": "mipsel",
    "os_version": "4.1.3",
    "entware": true
  },
  "capabilities": {
    "commands": {"ip": true, "ss": true, "iptables": true, "wg": false},
    "files": {"/proc/net/dev": true, "/opt/etc/init.d": true},
    "endpoints": {"rci_local": true, "http_rci": false}
  },
  "warnings": [
    {"code": "LOW_DISK", "message_key": "preflight.warn_low_disk", "params": {"free_mb": 42}},
    {"code": "NO_ROOT", "message_key": "preflight.warn_no_root"}
  ],
  "estimates": {
    "total_time_s": 120,
    "total_size_mb": 15,
    "cpu_peak_pct": 40,
    "ram_peak_mb": 32,
    "io_total_mb": 20
  },
  "collectors_summary": {
    "included": 12,
    "skipped": 5,
    "total": 17
  }
}
```

### 6.3. Структура plan.json (Step 65)

```json
{
  "schema_id": "plan",
  "schema_version": "1",
  "report_id": "kn3010-20260304T143022Z-a7f3",
  "timestamp": "2026-03-04T14:30:22Z",
  "research_mode": "medium",
  "performance_mode": "auto",
  "snapshot_mode": "incremental",
  "base_report_id": "kn3010-20260301T100000Z-b2c1",
  "tasks": [
    {
      "order": 1,
      "collector_id": "system.base",
      "status": "INCLUDE",
      "reason": "always_required",
      "dependencies": [],
      "timeout_s": 30,
      "budget": {"cpu_pct": 5, "ram_mb": 4, "io_mb": 1}
    },
    {
      "order": 2,
      "collector_id": "wifi.radio",
      "status": "SKIP",
      "reason": "no_wifi_detected",
      "dependencies": ["system.base"]
    }
  ]
}
```

---

## 7. Throttling и приоритеты (Steps 66–67)

### 7.1. Стратегия Throttling (Step 66)

```
max_workers = f(cpu_count, ram_free, loadavg, performance_mode)

Lite:   max_workers = 1, nice = 19, ionice = idle
Middle: max_workers = min(2, cpu_count), nice = 10
Hard:   max_workers = cpu_count, nice = 0
Auto:   dynamic — начинаем с 2, увеличиваем/снижаем по loadavg

Правило снижения:
  if loadavg_1min > cpu_count * threshold[mode]:
      workers -= 1 (минимум 1)
  if ram_free_pct < 15%:
      workers = 1, SKIP heavy collectors
  if disk_free_mb < min_free_mb (default 50):
      STOP mirroring, SOFT_FAIL large artifacts
```

### 7.2. Правило приоритетов (Step 67)

**Стабильность > Полнота.**

При перегрузке:
1. Пропускаются **heavy** collectors первыми (сортировка по `estimated_cost.time_s DESC`)
2. Сохраняются **всегда**: preflight, plan, event_log, debugger_report, manifest
3. Минимальный набор: `system.base` + `network.base`
4. Collectors с `SOFT_FAIL`/`SKIP` отмечаются в manifest с причиной

---

## 8. Root-эскалация (Step 68)

Стратегия: **без setuid**, только через `sudo`/`su` если доступно.

```
1. Collector с requires_root=true:
   a. Проверить: текущий uid == 0? → запускаем напрямую
   b. Проверить: sudo доступен без пароля (sudo -n true)? → sudo <cmd>
   c. Иначе: SKIP с причиной "no_root_access"
2. Никогда не запрашиваем пароль интерактивно
3. В логе фиксируется: использовалось ли повышение, какой метод
```

---

## 9. Контракт запуска collector (Steps 69–70)

### 9.1. Окружение (Step 69)

| Переменная | Описание |
|---|---|
| `COLLECTOR_WORKDIR` | Рабочий каталог (tmp/<session>/<collector_id>/) |
| `COLLECTOR_ID` | ID сборщика |
| `RESEARCH_MODE` | light\|medium\|full\|extreme |
| `PERF_MODE` | lite\|middle\|hard\|auto |
| `TIMEOUT_S` | Таймаут в секундах |
| `MAX_OUTPUT_MB` | Макс. размер вывода |
| `CONFIG_SUBSET` | Путь к подмножеству config для collector |
| `LANG` | ru\|en |
| `STATEDB_PATH` | Путь к StateDB (для incremental) |
| `IS_INCREMENTAL` | 0\|1 |

Выходные файлы (в `$COLLECTOR_WORKDIR`):
- `result.json` — **обязательно**
- `artifacts/` — файлы-артефакты (опционально)
- `logs/collector.log` — лог работы (опционально)

### 9.2. Модель ошибок (Step 70)

| Exit Code | Status | Описание |
|---|---|---|
| 0 | OK | Успешно |
| 0 + status=SKIP в result.json | SKIP | Нечего собирать (напр. нет изменений) |
| 1 | SOFT_FAIL | Частичный сбор, есть результаты |
| 2 | HARD_FAIL | Полный провал, нет полезных данных |
| 124/137 | TIMEOUT | Убит по таймауту (timeout/kill) |

При любом exit code CollectorsManager:
1. Читает `result.json` (если существует)
2. Если `result.json` нет → генерирует stub с `status=HARD_FAIL`
3. Записывает метрики (duration, output_size)
4. **Общий snapshot продолжается** — collector НИКОГДА не роняет весь процесс

## Стратегия повторов (Step 487)

| Режим | Max Retries | Логика |
|---|---|---|
| Lite | 0 | Без повторов — минимальная нагрузка |
| Middle | 1 | Один повтор для нестабильных collectors |
| Hard | 0 | Без повторов — не усугублять нагрузку |
| Auto | 1 | По решению Governor (если ресурсы позволяют) |

Фиксация: повторы применяются только для `SOFT_FAIL`; `HARD_FAIL` и `TIMEOUT` не повторяются.

## Collector Quarantine (Step 656)
Если collector постоянно падает (N раз подряд в StateDB), он помечается как disabled_until_upgrade
и не запускается автоматически до обновления.

## История статусов (Step 657)
StateDB хранит последние N запусков каждого collector для анализа стабильности.
Auto режим использует историю для оптимизации плана.
