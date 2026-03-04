# Policies — Политики

## Файлы

| Файл | Описание | Версионируется |
|---|---|---|
| `denylist.default.json` | Дефолтный denylist для зеркала (не менять) | да |
| `denylist.json` | Пользовательский denylist (merge поверх default) | да |
| `privacy.default.json` | Дефолтные правила privacy (не менять) | да |
| `privacy.json` | Пользовательские privacy правила | да |

## Дефолтный denylist (Step 319)

Блокированы по умолчанию:
- **Pseudo-FS**: `/proc`, `/sys`, `/dev` — бесконечные/виртуальные
- **Временные**: `/tmp`, `/var/tmp`
- **Self-mirror**: `$WORKDIR`, `$OUTPUT_DIR`, `$INSTALL_DIR` (CRITICAL)
- **Артефакты**: `*.tar.gz`, `*.zip`, `*.tar`, `*.bak`
- **Runtime**: `*.pid`, `*.sock`, `.git`, `__pycache__`

Пользователь может добавить свои пути через:
1. `policies/denylist.json` — файл (merge)
2. `config.mirror.denylist_extra` — массив в config (merge)
3. `config.mirror.allowlist` — исключения из denylist

## Версионирование (Step 320)

- Каждый policy file имеет `_policy_version`
- При обновлении продукта: merge default + user (user paths сохраняются)
- Backup перед миграцией: `*.pre-migration.bak`
