# WBS.md — Work Breakdown Structure / Декомпозиция модулей

## Модули системы

```
keenetic-debug/
├── Core                 — Оркестрация, plan, execute, resume, event log, cancellation
│   ├── Orchestrator     — Главный цикл: preflight → plan → execute → package
│   ├── TaskQueue        — Очередь задач с приоритетами и зависимостями
│   └── StateStore       — Внутреннее состояние выполнения + checkpoints
│
├── Installer            — install.sh, pinned sha256, offline bundle, rollback
│   ├── ArchDetect       — Определение mipsel/mips/aarch64
│   ├── Downloader       — Скачивание с проверкой хэшей
│   └── Upgrader         — Обновление + rollback
│
├── Configurator         — config.json, валидация, миграции, приоритеты
│   └── PolicyEngine     — denylist/allowlist, privacy, dangerous_ops
│
├── Preflight            — Проверки среды, capability detect, умный план
│   ├── CapabilityDetect — Обнаружение доступных команд/файлов
│   ├── CostEstimator    — Оценка ресурсов по профилю + StateDB
│   └── PlanBuilder      — Выбор collectors + причины включения/исключения
│
├── Governor             — CPU/RAM/DISK-IO мониторинг, throttling
│   ├── ResourceMonitor  — /proc/loadavg, /proc/meminfo, df
│   ├── WorkerManager    — Динамическое управление параллелизмом
│   └── CostBudget       — Бюджет ресурсов по performance_mode
│
├── CollectorsManager    — Реестр, зависимости, приоритеты, таймауты
│   ├── Registry         — Загрузка plugin.json, валидация
│   ├── Scheduler        — Планирование через Governor
│   └── Runner           — Запуск, изоляция, сбор результатов
│
├── Collectors (plugins) — 20+ модулей по категориям ТЗ п.5
│   ├── system.base      — /proc, ps, mount, df, dmesg
│   ├── network.base     — ip, route, ss, iptables
│   ├── network.deep     — conntrack, NAT, UPnP, DNS/DHCP
│   ├── wifi.radio       — Параметры радио, клиенты, RSSI
│   ├── vpn.status       — WireGuard/OpenVPN/IPsec/L2TP
│   ├── storage.fs       — Устройства, разделы, inode, top-N
│   ├── security.exposure— Порты, firewall, remote access, сертификаты
│   ├── config.keenetic  — KeeneticOS конфиги (ndm/rci)
│   ├── config.entware   — /opt/etc/*, opkg status
│   ├── hooks.ndm        — ndm hooks, зависимости
│   ├── services.entware — init.d, PID/порты
│   ├── scheduler.auto   — cron, autostart скрипты
│   ├── process.deep     — Дерево процессов, FD, ресурсы
│   ├── kernel.deep      — /proc/interrupts, modules, sysctl
│   ├── logs.system      — dmesg/syslog (лимитированно)
│   ├── telemetry.mini   — Сэмплинг CPU/RAM/net
│   ├── apps.websnap     — Web-панели, HTML слепки
│   ├── apps.api         — Поиск API/endpoints
│   ├── mirror.full      — Зеркалирование /opt (Full/Extreme)
│   └── _template        — Шаблон для нового collector
│
├── Adapters             — ndm/rcicli/http_rci/ssh + fallback
│   └── CapabilityLayer  — Detect, dry-run, audit log
│
├── AppManager           — Статус приложений, init.d, backup/restore
│
├── Packager             — Потоковая упаковка, sha256 «на лету», atomic rename
│   ├── Archiver         — tar.gz (основной), zip (опция)
│   └── ManifestBuilder  — manifest.json генерация
│
├── InventoryBuilder     — Корреляции порт→процесс→пакет→конфиг→endpoint
│
├── DeltaManager/StateDB — Индексы, курсоры, хэши, метрики
│   ├── StateDB          — Хранение состояния между запусками
│   └── ChainManager     — baseline/delta цепочка, rebase/compaction
│
├── ChecksEngine         — Проверки на основе baseline vs delta
│
├── RedactionEngine      — Классификация PII, mask/zeroize, отчёт
│
├── Debugger             — Аварийный отчёт (даже при crash)
│
├── WebUI                — Python HTTP API + static SPA
│   ├── APIServer        — REST endpoints + auth + rate limiting
│   └── Frontend         — Preflight, Inventory, Checks, Chain, Reports
│
├── CLI                  — `kd` command, --lang, неинтерактивный
│
└── UpdateManager        — Доставка обновлений, pinned versions, SBOM
```

## Интерфейсы между модулями (шаг 16)

| Источник → Получатель | Контракт | Формат | Версионируется |
|------------------------|----------|--------|----------------|
| Preflight → Core | preflight.json | JSON Schema | Да |
| Core → CollectorsManager | plan.json | JSON Schema | Да |
| Collector → CollectorsManager | result.json | JSON Schema | Да |
| CollectorsManager → Packager | артефакты + result.json | Файлы | — |
| Packager → Manifest | manifest.json | JSON Schema | Да |
| Collectors → InventoryBuilder | result.json (данные) | JSON Schema | Да |
| InventoryBuilder → ChecksEngine | inventory.json | JSON Schema | Да |
| StateDB → Preflight | state hints | Internal API | Да |
| RedactionEngine → Packager | redaction_report.json | JSON Schema | Да |
| Core → WebUI/CLI | progress events | JSONL stream | Да |
