# ASSUMPTIONS.md — Допущения / Assumptions

Допущения, явно **не зафиксированные** в ТЗ v1.4.
| A0 | Целевые архитектуры: mipsel, mips, aarch64 | ТЗ §1.2 | Сборки под каждую arch |

| # | Допущение | Влияние | Риск |
|---|-----------|---------|------|
| A1 | WebUI HTTP-сервер на Python ≥ 3.8 (Entware `python3` пакет) | WebUI недоступен без Python | fallback: Go static binary |
| A2 | Формат архива по умолчанию — `tar.gz` | Требуется `tar` + `gzip` (есть в BusyBox) | `zip` как опция |
| A3 | Минимальные версии утилит: BusyBox ≥ 1.30, ash совместимый shell | Часть BusyBox applets может отсутствовать | capability detect + fallback |
| A4 | `/opt` — точка монтирования Entware на USB/внутренней памяти | collectors зависят от `/opt/bin`, `/opt/etc` | detect + graceful skip |
| A5 | `opkg` доступен в PATH при наличии Entware | Используется для inventory packages | fallback: parse `/opt/lib/opkg/status` |
| A6 | NTP синхронизировано (ISO 8601 timestamps корректны) | timestamp drift в артефактах | используем также uptime |
| A7 | JSON Schema 2020-12 — диалект для всех контрактов | Требуется валидатор в CI и (опц.) в runtime | `ajv` CLI или Python `jsonschema` |
| A8 | Пользователь имеет доступ к SSH/telnet для запуска CLI | CLI неинтерактивен, но требует терминал | WebUI как альтернативный вход |
| A9 | USB-накопитель ext2/3/4 или NTFS с Entware на нём | `/opt/var`, `/opt/tmp` как workdir по умолчанию | detect FS type, warn on NAND |
| A10| Go fallback компилируется кросс-сборкой заранее для целевых arch | Не требует Go runtime на роутере | добавляет размер offline bundle |

## MVP → Release (шаг 2)

Обязательные компоненты поставки:

1. **Core** — оркестрация, plan, execute, resume
2. **Collectors** — минимум 20 ключевых (по категориям ТЗ)
3. **Packager** — потоковая упаковка + manifest + sha256
4. **WebUI** — HTTP API + SPA, bearer token auth, readonly/admin
5. **CLI** — `kd` (keenetic-debug), --lang ru|en, неинтерактивный
6. **install.sh** — one-command install, pinned sha256, offline bundle
7. **Документация** — RU/EN, 100% покрытие, CI-validated
8. **CI** — lint, schema validation, l10n coverage, golden snapshots
