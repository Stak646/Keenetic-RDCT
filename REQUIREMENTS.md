# REQUIREMENTS.md — Реестр обязательных требований

> Источник: ТЗ v1.4. Выписаны все MUST / ОБЯЗАТЕЛЬНО / CRITICAL требования.

## Функциональные требования

### F-CORE: Ядро и оркестрация

| ID | Требование | ТЗ раздел | Приоритет |
|----|-----------|-----------|-----------|
| F-CORE-01 | Оркестрация модулей: plan → execute → package | §4.1 | MUST |
| F-CORE-02 | Управление режимами research/performance | §4.1, §6, §7 | MUST |
| F-CORE-03 | State store + event log + cancellation | §4.1 | MUST |
| F-CORE-04 | Чекпоинты и resume на уровне задач/сборщиков | §4.1 | MUST |
| F-CORE-05 | Watchdog с глобальным таймаутом | §4.1 | MUST |

### F-COLL: Коллекторы

| ID | Требование | ТЗ раздел | Приоритет |
|----|-----------|-----------|-----------|
| F-COLL-01 | Каждый collector — отдельный модуль с plugin.json + result.json | §4.8 | MUST |
| F-COLL-02 | Capability-driven: проверка доступности, fallback | §4, §4.8 | MUST |
| F-COLL-03 | Запуск в отдельном процессе с timeout и max_output_mb | §4.8.3 | MUST |
| F-COLL-04 | Статусы: OK/SKIP/SOFT_FAIL/HARD_FAIL/TIMEOUT | §4.8.3 | MUST |
| F-COLL-05 | privacy_tags и estimated_cost обязательны в plugin.json | §4.8.1 | MUST |
| F-COLL-06 | Поддержка incremental: fingerprint + delta-результат | §4.8.1, §5 | MUST |
| F-COLL-07 | 20+ коллекторов по категориям §5 | §5.1–§5.11 | MUST |

### F-DATA: Сбор данных

| ID | Требование | ТЗ раздел | Приоритет |
|----|-----------|-----------|-----------|
| F-DATA-01 | Конфигурации KeeneticOS + Entware | §5.1 | MUST |
| F-DATA-02 | ndm hooks и зависимости | §5.2 | MUST |
| F-DATA-03 | Сервисы Entware (init.d, PID/порты) | §5.3 | MUST |
| F-DATA-04 | Сетевые параметры (ip/route/ss/firewall) | §5.4 | MUST |
| F-DATA-05 | Доступность RCI/HTTP endpoints (safe-запросы) | §5.5 | MUST |
| F-DATA-06 | Системные сведения (/proc, ps, dmesg, mount, df) | §5.6 | MUST |
| F-DATA-07 | Данные о процессах (дерево, FD, ресурсы) | §5.7 | MUST |
| F-DATA-08 | Логи инструмента (JSONL + human-readable) | §5.8 | MUST |
| F-DATA-09 | Сеть углублённо (conntrack, NAT, DNS/DHCP, QoS) | §5.11.1 | MUST |
| F-DATA-10 | Wi-Fi/Radio (каналы, клиенты, RSSI) | §5.11.2 | MUST |
| F-DATA-11 | VPN/туннели (WireGuard/OpenVPN/IPsec/L2TP) | §5.11.3 | MUST |
| F-DATA-12 | Хранилище/USB/ФС (устройства, inode, top-N) | §5.11.4 | MUST |
| F-DATA-13 | Безопасность/экспозиция (порты, firewall, remote access) | §5.11.5 | MUST |
| F-DATA-14 | Планировщики/автозапуск (cron, ndm, init.d) | §5.11.6 | MUST |
| F-DATA-15 | Мини-телеметрия (CPU/RAM/net сэмплинг) | §5.11.7 | SHOULD |
| F-DATA-16 | Kernel/OS углублённо (/proc/interrupts, modules, sysctl) | §5.11.8 | SHOULD |
| F-DATA-17 | Приложения и web-слепки | §5.11.9 | SHOULD |
| F-DATA-18 | Поиск API и корреляции | §5.11.10 | SHOULD |
| F-DATA-19 | Полное зеркалирование /opt (Full/Extreme) | §5.9 | MUST (Full+) |

### F-SNAP: Snapshot и артефакты

| ID | Требование | ТЗ раздел | Приоритет |
|----|-----------|-----------|-----------|
| F-SNAP-01 | Потоковая упаковка tar.gz + sha256 «на лету» | §4.12 | MUST |
| F-SNAP-02 | Manifest.json в каждом snapshot | §4.12, §8.1 | MUST |
| F-SNAP-03 | Атомарная публикация (temp → rename) | §4.12 | MUST |
| F-SNAP-04 | Redaction report обязателен | §4.16 | MUST |
| F-SNAP-05 | Inventory.json с корреляциями | §4.13 | MUST |
| F-SNAP-06 | Checks.json (baseline vs delta) | §4.15 | MUST |
| F-SNAP-07 | Debugger report даже при аварийном завершении | §4.11 | MUST |

### F-INC: Инкрементальные снимки

| ID | Требование | ТЗ раздел | Приоритет |
|----|-----------|-----------|-----------|
| F-INC-01 | StateDB: индексы, курсоры, хэши, метрики | §4.14 | MUST |
| F-INC-02 | Цепочка baseline/delta, chain_max_depth | §4.14 | MUST |
| F-INC-03 | Rebase/compaction по политике | §4.14 | MUST |
| F-INC-04 | API: get_base(), record_run(), diff_index(), plan_from_state() | §4.14 | MUST |

### F-CHK: Проверки

| ID | Требование | ТЗ раздел | Приоритет |
|----|-----------|-----------|-----------|
| F-CHK-01 | Config drift detection | §8.8 | MUST |
| F-CHK-02 | Package changes | §8.8 | MUST |
| F-CHK-03 | Network exposure | §8.8 | MUST |
| F-CHK-04 | Process anomalies | §8.8 | MUST |
| F-CHK-05 | Storage growth | §8.8 | MUST |
| F-CHK-06 | Log anomalies | §8.8 | MUST |

## Нефункциональные требования

### NF-SEC: Безопасность

| ID | Требование | ТЗ раздел | Приоритет |
|----|-----------|-----------|-----------|
| NF-SEC-01 | Safe-by-default: readonly=true, dangerous_ops=false | §3 | CRITICAL |
| NF-SEC-02 | WebUI bind localhost/LAN, запрет 0.0.0.0 | §8.5 | CRITICAL |
| NF-SEC-03 | Bearer token auth обязателен | §8.5 | CRITICAL |
| NF-SEC-04 | Роли: readonly/admin | §8.5 | MUST |
| NF-SEC-05 | CSRF protection | §8.5 | MUST |
| NF-SEC-06 | Rate limiting | §8.5 | MUST |
| NF-SEC-07 | Redaction PII в Light/Medium | §4.16 | CRITICAL |
| NF-SEC-08 | Denylist включает workdir/output_dir/archives | §3.5 | CRITICAL |
| NF-SEC-09 | Запрет самозеркалирования (CRITICAL при нарушении) | §3.5, §3.6 | CRITICAL |
| NF-SEC-10 | Least privilege для Core/WebUI/CLI | §3 | MUST |

### NF-REL: Надёжность

| ID | Требование | ТЗ раздел | Приоритет |
|----|-----------|-----------|-----------|
| NF-REL-01 | Fault isolation: crash collector ≠ crash snapshot | §4.8.3 | MUST |
| NF-REL-02 | ENOSPC handling: partial snapshot + отчёт | §3 | MUST |
| NF-REL-03 | OOM handling: Governor throttle | §4.5 | MUST |
| NF-REL-04 | Timeout enforcement per-collector + watchdog | §4.8.3 | MUST |
| NF-REL-05 | Graceful degradation: snapshot ALWAYS completes | §4.8.3 | MUST |

### NF-PERF: Производительность

| ID | Требование | ТЗ раздел | Приоритет |
|----|-----------|-----------|-----------|
| NF-PERF-01 | Governor: мониторинг CPU/RAM/IO, throttling | §4.5 | MUST |
| NF-PERF-02 | nice/ionice при наличии | §4.5 | SHOULD |
| NF-PERF-03 | Streaming-first: без накопления гигабайтов | §4 | MUST |

### NF-CONT: Контракты данных

| ID | Требование | ТЗ раздел | Приоритет |
|----|-----------|-----------|-----------|
| NF-CONT-01 | Все артефакты валидируются JSON Schema 2020-12 | §4.8.2 | MUST |
| NF-CONT-02 | schema_id + schema_version в каждом файле | §4.8.2 | MUST |
| NF-CONT-03 | Совместимость Core vX читает [X-1…X] | §4.8.2 | MUST |

## Эксплуатационные требования

| ID | Требование | ТЗ раздел | Приоритет |
|----|-----------|-----------|-----------|
| OP-01 | One-command install.sh | §4.2 | MUST |
| OP-02 | Pinned sha256 для компонентов | §4.2 | MUST |
| OP-03 | Offline bundle support | §4.2 | MUST |
| OP-04 | Rollback при сбое установки | §4.2 | MUST |
| OP-05 | Архитектуры: mipsel, mips, aarch64 | §2 | MUST |
| OP-06 | Автопоиск порта WebUI (5000-5099) | §8.5 | MUST |

## Документационные требования

| ID | Требование | ТЗ раздел | Приоритет |
|----|-----------|-----------|-----------|
| DOC-01 | Документация RU/EN — часть продукта | §9 | MUST |
| DOC-02 | 100% покрытие RU/EN (синхронная структура) | §9 | MUST |
| DOC-03 | CI-валидация документации | §9 | MUST |
| DOC-04 | i18n: запрет смешения языков | §9, §8.6 | MUST |
