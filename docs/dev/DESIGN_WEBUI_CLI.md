# DESIGN_WEBUI_CLI.md — WebUI, API, CLI, AppManager, Packager, надёжность

> Шаги 80–98 плана.

---

## 1. Модель WebUI (Step 80)

Минимальный **Python HTTP-сервер** + **статический SPA** (vanilla JS/HTML).

```
web/
├── server.py              # http.server + routing, JSON API
└── static/
    ├── index.html
    ├── app.js
    └── style.css
```

Принципы:
- **Никаких фреймворков** на бэкенде (только stdlib: `http.server`, `json`, `os`)
- Фронтенд: vanilla JS + minimal CSS, без сборки
- Без WebSocket в MVP — polling через `/api/progress` (каждые 2 сек)
- Fallback: если Python недоступен, WebUI = disabled, только CLI

---

## 2. API Security Model (Step 81)

| Параметр | Значение по умолчанию | Настройка |
|---|---|---|
| **Bind** | `127.0.0.1` | `config.webui.bind` (запрещён `0.0.0.0` по умолчанию) |
| **Auth** | Bearer token (header `Authorization: Bearer <token>`) | Генерируется при install |
| **Роли** | `readonly` (просмотр/скачивание), `admin` (управление/delete/restore/dangerous) | В token metadata |
| **Token storage** | `var/.auth_token` (chmod 600) | — |
| **LAN режим** | Bind на LAN IP (config), доступен из LAN | `config.webui.bind` |

### Генерация token

```shell
token=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
echo "$token" > var/.auth_token
chmod 600 var/.auth_token
```

Два токена: `admin_token`, `readonly_token` — либо один token с metadata файлом `var/.auth_roles.json`.

---

## 3. CSRF Policy (Step 82)

Подход: **Bearer token only** (без cookies).

| Мера | Реализация |
|---|---|
| Без cookies | Токен только в `Authorization` header |
| Origin check | Сервер проверяет `Origin`/`Referer` — должен совпадать с bind address |
| No CORS | `Access-Control-Allow-Origin` не выставляется (или только bind host) |
| Preflight | `OPTIONS` возвращает 403 для чужих Origin |

Если в будущем добавятся cookies/сессии — обязательны CSRF-токены + SameSite=Strict.

---

## 4. Rate Limiting (Step 83)

Реализация: in-memory counter по IP + sliding window.

| Категория | Лимит | Окно |
|---|---|---|
| Общие API запросы | 60 req | 1 мин |
| Тяжёлые (`/download`, `/delete`, `/start`) | 5 req | 1 мин |
| Auth fail | 10 попыток | 5 мин (после — блок на 15 мин) |

Ответ при превышении: `429 Too Many Requests` + `Retry-After` header.

---

## 5. API Endpoints (Step 84)

| Метод | Путь | Роль | Описание |
|---|---|---|---|
| GET | `/health` | — | `{"status":"ok","version":"..."}` (без auth) |
| GET | `/api/metrics` | readonly | Метрики Governor (опц.) |
| POST | `/api/preflight` | admin | Запуск preflight, возвращает plan |
| POST | `/api/start` | admin | Запуск сбора |
| POST | `/api/stop` | admin | Остановка/отмена |
| GET | `/api/progress` | readonly | Текущий прогресс + per-collector статус |
| GET | `/api/reports` | readonly | Список snapshot'ов |
| GET | `/api/report/<id>` | readonly | Метаданные snapshot'а |
| GET | `/api/report/<id>/download` | readonly | Скачать tar.gz |
| DELETE | `/api/report/<id>` | admin | Удалить snapshot |
| GET | `/api/report/<id>/manifest` | readonly | manifest.json |
| GET | `/api/report/<id>/inventory` | readonly | inventory.json |
| GET | `/api/report/<id>/checks` | readonly | checks.json |
| GET | `/api/report/<id>/redaction` | readonly | redaction_report.json |
| GET | `/api/chain` | readonly | Цепочка baseline/delta |
| POST | `/api/chain/rebase` | admin | Принудительный rebase |
| GET | `/api/apps` | readonly | Список приложений |
| POST | `/api/app/<n>/restart` | admin | Рестарт сервиса (dangerous_ops) |
| GET | `/api/config` | admin | Текущий config |
| PUT | `/api/config` | admin | Обновить config |
| POST | `/api/sanitize/<id>` | admin | Post-hoc sanitize snapshot |

---

## 6. Формат прогресса (Step 85)

Файл `run/progress.json`, обновляемый каждые 2 секунды:

```json
{
  "state": "RUNNING",
  "report_id": "kn3010-20260304T143022Z-a7f3",
  "started_at": "2026-03-04T14:30:22Z",
  "overall_pct": 45,
  "current_collector": "network.deep",
  "queue": ["wifi.radio", "vpn.status", "storage.fs"],
  "completed": [
    {"id": "system.base", "status": "OK", "duration_ms": 2100},
    {"id": "network.base", "status": "OK", "duration_ms": 3400}
  ],
  "failed": [],
  "governor": {
    "workers_active": 2,
    "cpu_pct": 35,
    "ram_used_pct": 42,
    "disk_free_mb": 180,
    "throttled": false
  }
}
```

---

## 7. Автопоиск порта WebUI (Steps 86–87)

### 7.1. Алгоритм (Step 86)

```
PORT_RANGE = [5000, 5099]   # детерминированный диапазон
manual_port = config.webui.port   # null = auto

if manual_port:
  if is_free(manual_port):
    use(manual_port)
  else:
    log(ERROR, "port_in_use", port=manual_port)
    fallback → auto
    
for port in PORT_RANGE:
  if is_free(port):
    use(port)
    break
else:
  log(CRITICAL, "no_free_port", range=PORT_RANGE)
  exit 1 с локализованным сообщением + remediation hint

is_free(port):
  попытка bind на (bind_addr, port) → success/fail
```

### 7.2. Сохранение порта (Step 87)

```shell
echo "$CHOSEN_PORT" > run/webui.port      # для CLI/диагностики
log_event("webui_port_selected", port=$CHOSEN_PORT)  # event log
echo "WebUI: http://${BIND_ADDR}:${CHOSEN_PORT}/"    # CLI stdout
```

---

## 8. CLI (Steps 88–89)

### 8.1. Требования (Step 88)

- **Неинтерактивный** по умолчанию (все параметры через флаги)
- `--lang ru|en` — глобальный флаг, приоритет: флаг > config.lang > env LANG > fallback "en"
- Выводит URL WebUI при старте
- `--json` — вывод в JSON (для автоматизации)
- `--quiet` / `--verbose` — уровни вывода

### 8.2. Опасные команды (Step 89)

Требуют `admin` role + `dangerous_ops=true` в config:

| Команда | Требование |
|---|---|
| `tool app restart <n>` | admin + dangerous_ops |
| `tool app restore <n>` | admin + dangerous_ops |
| `tool report delete <id>` | admin |
| `tool chain rebase` | admin |
| `tool chain compact` | admin |
| `tool config set dangerous_ops true` | admin (интерактивное подтверждение при --interactive) |

При попытке без прав → ошибка с локализованным сообщением.

---

## 9. AppManager (Step 90)

### 9.1. Обнаружение сервисов

```
1. Сканировать /opt/etc/init.d/S*
2. Для каждого скрипта:
   a. Определить имя сервиса (basename без SNN_ префикса)
   b. Проверить: executable? enabled? (есть /opt/etc/init.d/SNN_xxx)
   c. Вызвать: /opt/etc/init.d/SNN_xxx check → running/stopped
   d. Найти PID: через pid-файл или ps | grep
   e. Привязать PID → порты (ss -tlnp | grep pid)
3. Результат: apps_status.json
```

### 9.2. Backup/Restore

```
backup(app):
  1. Определить config_paths (из plugin.json или эвристика)
  2. tar -czf var/backups/<app>-<timestamp>.tar.gz <config_paths>
  3. Audit log: "backup", app, paths, size

restore(app, backup_id):   # dangerous_ops=true required
  1. Проверить dangerous_ops
  2. dry-run: показать что будет восстановлено
  3. Если --confirm: распаковать, перезаписать, рестарт
  4. Audit log: "restore", app, backup_id
```

---

## 10. InventoryBuilder (Steps 91–93)

### 10.1. Корреляция (Step 91)

```
1. ss -tulnp → listening_ports[]
2. Для каждого порта:
   port → pid (из ss output)
   pid → executable (readlink /proc/<pid>/exe или ps)
   executable → opkg_package (через opkg search)
   opkg_package → config_paths (через opkg list-files + эвристика /opt/etc/<pkg>*)
   config_paths → detect endpoints (regex/hardcoded patterns)
3. Результат: inventory.json с уровнем доверия (detected|confirmed)
```

### 10.2. Обнаружение opkg package (Step 92)

```shell
# Способ 1: opkg search (если доступен)
pkg=$(opkg search "$executable" 2>/dev/null | head -1 | awk '{print $1}')

# Способ 2: opkg list-files (кешированный)
# При первом запуске: opkg list-installed → кеш пакетов
# Затем: opkg files <pkg> → кеш файлов
# Lookup: бинарник → какой пакет владеет

# Fallback: basename executable → совпадение с именем пакета
```

**Кеширование**: результат `opkg list-installed` кешируется в StateDB (inventory_state) на время сессии.

### 10.3. HTTP Endpoint Discovery (Step 93)

```
allowlist_ports = [80, 443, 8080, 8443, 3000, 9090, ...]  # из config
allowlist_paths = ["/", "/api", "/status", "/health"]

Для каждого listening port в allowlist:
  1. HTTP GET http://127.0.0.1:<port>/ → заголовки + первые 4KB body
  2. HTTP HEAD http://127.0.0.1:<port>/ → заголовки (ETag, Last-Modified)
  3. НЕ передаём credentials
  4. Таймаут: 5 сек на запрос
  5. Логируем каждый запрос в event_log (активная проверка)
  6. Результат: detected_endpoints[]
```

**Ограничения**:
- Только localhost (127.0.0.1)
- Только GET/HEAD, без POST/PUT/DELETE
- Без brute-force путей
- Без авторизации (только публичные страницы)
- Маркируются как `dangerous` если не в allowlist → требуют `dangerous_ops=true`

---

## 11. Resource Consumption Prevention (Step 94)

Все «тяжёлые» API endpoints обязаны проходить через Governor:

| Endpoint | Ограничение |
|---|---|
| `/api/start` | Одновременно только 1 сессия сбора |
| `/api/report/<id>/download` | Rate limit + max concurrent downloads = 2 |
| `/api/chain/rebase` | Блокирует другие операции с StateDB |
| `/api/sanitize/<id>` | Under Governor, timeout |

Каждый heavy endpoint:
1. Проверяет Governor.can_proceed()
2. Регистрирует задачу
3. Имеет timeout
4. При timeout → 504 Gateway Timeout

---

## 12. Packager (Step 95)

### 12.1. Потоковое создание

```
1. Открыть temp файл: tmp/<session>/snapshot.tar.gz.tmp
2. tar cz --to-stdout ... | tee >(sha256sum > manifest_hash) > tmp_file
3. Параллельно для каждого файла: sha256sum → записать в manifest
4. Финал:
   fsync(tmp_file)  # если доступен
   mv tmp_file var/reports/<report_id>/snapshot.tar.gz  # атомарный rename
5. Записать manifest.json рядом
```

### 12.2. Атомарность

- **temp → fsync → rename** — гарантирует, что при crash не останется corrupt файл
- Если `fsync` недоступен (BusyBox) — `sync` перед rename
- Manifest содержит sha256 **каждого** файла внутри архива

---

## 13. Поведение при ENOSPC (Step 96)

```
Governor monitors disk_free_mb continuously

if disk_free_mb < critical_threshold (default 20MB):
  1. Немедленно остановить: mirror.full, telemetry.mini, apps.websnap
  2. Все активные collectors → signal STOP
  3. Продолжить минимальный snapshot:
     - preflight.json ✓
     - plan.json ✓
     - event_log.jsonl ✓ (truncate если нужно)
     - debugger_report.json ✓
     - manifest.json ✓ (с ENOSPC flag)
  4. Пометить manifest: "enospc": true, "enospc_detail": "..."
  5. Попытаться упаковать partial snapshot
  6. Если даже упаковка не помещается → сохранить только manifest + logs (без tar.gz)
```

---

## 14. Поведение при OOM/перегрузке (Step 97)

```
Governor monitors:
  - /proc/meminfo (MemAvailable)
  - /proc/loadavg

if ram_available_pct < 15%:
  1. Снизить workers до 1
  2. SKIP/SOFT_FAIL heavy collectors (sorted by ram_mb DESC)
  3. Логировать причину

if loadavg_1min > cpu_count * 2.0:
  1. Снизить workers
  2. Увеличить nice (если доступен renice)
  3. Пропустить telemetry/mirror/websnap

Фиксация в checks/summary:
  {"id": "governor.resource_pressure", "severity": "WARN",
   "evidence": {"ram_available_pct": 8, "action": "skipped_heavy_collectors"}}
```

---

## 15. Метрики профилирования (Step 98)

Для каждого collector, записываемые в StateDB (`run_metrics`):

| Метрика | Тип | Описание |
|---|---|---|
| `duration_ms` | int | Время выполнения |
| `cpu_pct_est` | float | Оценка CPU (loadavg до/после) |
| `io_mb` | float | Объём I/O (разница /proc/diskstats) |
| `output_mb` | float | Размер выходных артефактов |
| `status` | string | OK/SKIP/SOFT_FAIL/HARD_FAIL/TIMEOUT |
| `timeout_hit` | bool | Был ли timeout |
| `retries` | int | Количество повторных попыток (если retry enabled) |

Используются:
- **Auto** mode: выбор стратегии параллелизма
- **Smart plan** (incremental): предсказание стоимости
- **WebUI /api/metrics**: отображение затрат

---

## 16. Запрещённые дефолты (Step 106)

CI-проверка `safe-defaults-check`:

| Параметр | Запрещённое значение | Безопасный дефолт |
|---|---|---|
| `webui.bind` | `0.0.0.0` | `127.0.0.1` |
| `dangerous_ops` | `true` | `false` |
| `readonly` | `false` | `true` |
| Auth token | отсутствует | генерируется при install |
| Mirror denylist | пустой | заполненный (policies/denylist.json) |
| Collector timeout | отсутствует / 0 | обязательно > 0 |
| Governor limits | отсутствуют | заполнены |

---

## 17. Стратегия релизов (Step 107)

- **GitHub Releases**: каждый тег vX.Y.Z → Release
- Артефакты: `keenetic-debug-<version>-online.tar.gz` (без Python/бинарей) + `keenetic-debug-<version>-offline-<arch>.tar.gz` (с зависимостями)
- Release notes: из CHANGELOG.md, совместимость схем, breaking changes
- install.sh: pinned sha256 для каждого артефакта

---

## 18. План миграций (Step 108)

При обновлении версии:

```
1. Configurator.migrate(config.json):
   - Читает config_version
   - Применяет миграции последовательно (v1→v2→v3...)
   - Добавляет новые поля с дефолтами
   - Удаляет устаревшие поля
   - Пишет backup: config.json.bak

2. DeltaManager.migrate(state.db):
   - Проверяет schema_version StateDB
   - ALTER TABLE / добавляет новые columns
   - Если major version change → пересоздание StateDB (новый baseline)

3. Старые snapshot'ы:
   - Не модифицируются
   - Core читает schema_version [X-1…X]
   - Если schema_version < X-1 → SKIP с рекомендацией
```

---

## 19. Работа без Entware (Step 109)

| Функциональность | Без Entware | С Entware |
|---|---|---|
| system.base | ✓ (BusyBox) | ✓ |
| network.base | ✓ (ip/ss из KeeneticOS) | ✓ |
| config.keenetic | ✓ | ✓ |
| config.entware | ✗ | ✓ |
| config.opkg | ✗ | ✓ |
| services.initd | ✗ | ✓ |
| WebUI | ✗ (нет Python) | ✓ |
| Все deep collectors | ✗ | ✓ |
| StateDB (SQLite) | Fallback JSON | ✓ |
| CLI | ✓ (ash) | ✓ |

**Правило**: без Entware — только «Light mode + Lite perf» с минимальным набором collectors. CLI выводит предупреждение.

---

## 20. Support Playbook (Step 110)

### Типичные сценарии

**1. Быстрый сбор для поддержки**
```shell
keenetic-debug start --mode light --perf lite
# → URL для скачивания snapshot
```

**2. Скачивание snapshot**
```shell
keenetic-debug report list
keenetic-debug report download <id> --output /tmp/
```

**3. Sanitize перед отправкой**
```shell
keenetic-debug sanitize <report_id>
# → Создаёт <report_id>.sanitized.tar.gz с максимальной редакцией
```

**4. Включение debug**
```shell
keenetic-debug config set debug true
keenetic-debug start --mode medium --perf middle --verbose
# → Расширенные логи в event_log.jsonl
```

**5. Инкрементальный мониторинг**
```shell
keenetic-debug start --baseline --mode medium
# ... через некоторое время ...
keenetic-debug start --incremental
keenetic-debug checks show
```

**6. Проверка здоровья WebUI**
```shell
curl -s http://127.0.0.1:$(cat /opt/keenetic-debug/run/webui.port)/health
```

## WebUI: Chain View Page (Step 930)
Визуализация цепочки baseline/deltas: timeline, размеры, кнопки Rebase/Compact (disabled без dangerous_ops/admin).

## WebUI: Checks Page (Step 931)
Сводка изменений/аномалий с фильтрами по категориям: порты, процессы, пакеты, конфиги, маршруты, firewall, логи, Wi-Fi, VPN, storage.
Экспорт в JSON/HTML для поддержки.
