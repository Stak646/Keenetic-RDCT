# ARCHITECTURE_PRINCIPLES.md — Архитектурные принципы

## Базовые принципы (ТЗ п.4)

### 1. Safe-by-Default
- Режим **readonly** по умолчанию; запись только в workdir/output_dir.
- `dangerous_ops=false` по умолчанию; опасные действия требуют явного включения.
- WebUI bind: `127.0.0.1` (или LAN); запрет `0.0.0.0`.
- Bearer token обязателен; роли `readonly` / `admin`.
- Denylist включает workdir, output_dir, архивы, tmp.

### 2. Capability-Driven
- Collectors не «гадают» о командах/файлах/эндпоинтах.
- Перед выполнением — capability detect: проверка наличия команд, файлов, прав.
- Каждая необязательная зависимость имеет fallback или SKIP.

### 3. Streaming-First
- Упаковка и хэширование результатов «на лету».
- Без накопления гигабайтов во временной папке.
- sha256 считается параллельно с записью.

### 4. Fault Isolation
- Каждый collector — отдельный процесс с timeout и max_output_mb.
- Crash/timeout одного collector НЕ роняет весь snapshot.
- Статусы: `OK` | `SKIP` | `SOFT_FAIL` | `HARD_FAIL` | `TIMEOUT`.
- Общий snapshot **всегда** завершается с отчётом, даже при ошибках.

### 5. Контракты как продукт
- Все артефакты валидируются JSON Schema (2020-12).
- Каждый файл содержит `schema_id` и `schema_version`.
- Совместимость: Core vX читает schema_version [X-1 … X].

## Модель угроз и безопасности (шаги 6, 19-20)

### Опасные операции (`dangerous_ops=true` required)
- restart/restore/modify config сервисов
- Активные HTTP-запросы к эндпоинтам (за рамками allowlist)
- Глубокие сканы (full mirror, exhaustive port scan)
- Удаление snapshot'ов / restore из backup

### Критические риски и mitigation

| Риск | Mitigation |
|------|-----------|
| **ENOSPC** | Governor мониторит `df`; при <5% free — stop heavy collectors, partial snapshot |
| **OOM** | Governor мониторит `/proc/meminfo`; снижение workers, SKIP heavy |
| **Самозеркалирование** | Denylist включает workdir/output_dir/archives; детект рекурсии/циклов |
| **Зависший collector** | per-collector `timeout_s` + глобальный watchdog |
| **Конфликт порта WebUI** | Автопоиск в диапазоне 5000-5099, fallback, логирование |
| **Утечка секретов** | Redaction engine Light/Medium: mask/zeroize; отчёт обязателен |
| **Supply-chain подмена** | install.sh: pinned sha256, проверка целостности, (опц.) подпись |

## Модель режимов (шаг 13)

### Research Mode — глубина сбора данных

| Параметр | Light | Medium | Full | Extreme |
|----------|-------|--------|------|---------|
| Конфиги | Базовые | + Entware | + скрытые | + все доступные |
| Сеть | ip/route/ss | + conntrack/NAT | + deep scan | + активные проверки |
| Приватность | Mask all PII | Mask all PII | As-is + отчёт | As-is + отчёт |
| Зеркало | Нет | Ключевые каталоги | /opt полностью | /opt + KeeneticOS |
| Web-слепки | Нет | Заголовки | HTML + ресурсы | + скриншоты |

### Performance Mode — нагрузка на систему

| Параметр | Lite | Middle | Hard | Auto |
|----------|------|--------|------|------|
| Workers | 1 | 2 | max(CPU) | dynamic |
| CPU limit | 30% | 50% | 80% | adaptive |
| IO throttle | Strict | Moderate | Minimal | Adaptive |
| Heavy collectors | SKIP | Subset | All | By budget |
| Telemetry sampling | 300s | 60s | 30s | Adaptive |

## Graceful Degradation (шаг 35)

```
collector status flow:
  detect_capabilities()
    → OK:     execute() → result.json (status=OK)
    → SKIP:   result.json (status=SKIP, reason="missing_dep: <cmd>")
    → FAIL:   result.json (status=SOFT_FAIL|HARD_FAIL, reason=...)
    → TIMEOUT: result.json (status=TIMEOUT, duration=N)

  snapshot ALWAYS completes with:
    - preflight.json
    - plan.json
    - manifest.json
    - debugger_report.json
    - event_log.jsonl
```

## Атомарность (шаг 36)

1. Все артефакты строятся в `$WORKDIR/tmp/<report_id>/`
2. После завершения: `fsync` (если доступен) → `mv` (atomic rename) в output_dir
3. При сбое: `tmp/` содержит diagnosable traces + debugger report

## Запрет самозеркалирования (шаги 37-38)

- Default denylist: `workdir`, `output_dir`, `*.tar.gz`, `*.zip`, `/tmp`
- Symlinks: по умолчанию НЕ следовать; логировать в `excluded.json`
- Cycle detection: inode tracking для обхода файловой системы
- При нарушении: **CRITICAL** stop + запись причины
