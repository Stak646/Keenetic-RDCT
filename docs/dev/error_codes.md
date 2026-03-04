# Error Codes — Коды ошибок

## CLI / Core

| Code | Const | RU | EN |
|---|---|---|---|
| E001 | ERR_CONFIG_INVALID | Некорректная конфигурация | Invalid configuration |
| E002 | ERR_NO_DISK_SPACE | Недостаточно свободного места | Insufficient disk space |
| E003 | ERR_PORT_UNAVAILABLE | Не удалось найти свободный порт | No free port available |
| E004 | ERR_AUTH_FAILED | Неверный токен авторизации | Invalid auth token |
| E005 | ERR_DANGEROUS_DISABLED | Операция требует dangerous_ops=true | Operation requires dangerous_ops=true |
| E006 | ERR_NO_ROOT | Нет прав root для этого сборщика | No root access for this collector |
| E007 | ERR_SELF_MIRROR | Обнаружено самозеркалирование | Self-mirroring detected |
| E008 | ERR_STATEDB_MISMATCH | Fingerprint устройства не совпадает | Device fingerprint mismatch |
| E009 | ERR_CHAIN_TOO_DEEP | Цепочка дельт слишком глубокая | Delta chain too deep |
| E010 | ERR_NO_BASELINE | Не найден baseline для инкремента | No baseline found for increment |
| E011 | ERR_COLLECTOR_TIMEOUT | Сборщик превысил таймаут | Collector timed out |
| E012 | ERR_OOM_PRESSURE | Критическая нехватка памяти | Critical memory pressure |
| E013 | ERR_ENTWARE_MISSING | Entware не обнаружен | Entware not detected |
| E014 | ERR_USB_REQUIRED | Требуется USB-накопитель | USB storage required |
| E015 | ERR_HASH_MISMATCH | Контрольная сумма не совпадает | Hash mismatch |

## Installer

| Code | Const | RU | EN |
|---|---|---|---|
| I001 | ERR_UNSUPPORTED_ARCH | Неподдерживаемая архитектура | Unsupported architecture |
| I002 | ERR_DOWNLOAD_FAILED | Ошибка скачивания | Download failed |
| I003 | ERR_INTEGRITY_FAILED | Проверка целостности не пройдена | Integrity check failed |

## Правила
- Каждый код имеет RU и EN в i18n/ru.json и i18n/en.json
- Ключ i18n: `errors.E001`, `errors.I001` и т.д.
- Код возвращается в JSON output при `--json`

## Классификация ошибок (Step 469-470)

| Класс | Exit Code | Severity | Примеры |
|---|---|---|---|
| `user_error` | 2 | WARN | Невалидный config, неверные параметры CLI |
| `env_error` | 1 | WARN | Нет Entware, нет утилит, нет root |
| `resource_error` | 1 | CRIT | ENOSPC, OOM, timeout |
| `internal_error` | 2 | CRIT | Bug в Core, unexpected exception |

Exit codes связаны с severity в checks и CLI:
- 0 = OK (INFO)
- 1 = SOFT_FAIL (WARN) — env/resource проблема, snapshot создан частично
- 2 = HARD_FAIL (CRIT) — user/internal ошибка, snapshot может быть неполным
- 124/137 = TIMEOUT (CRIT) — ресурсная проблема
