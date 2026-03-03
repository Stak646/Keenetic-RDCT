# Справочник конфигурации (MVP)

Конфиг находится в `config/rdct.json` (внутри USB‑базы).

## Основные секции

### `server`

- `enabled`: `true|false` — включить WebUI/API
- `bind`: адрес (обычно `0.0.0.0`)
- `port`: порт (`0` = auto)
- `token`: токен для API

### `modes`

- `research_mode`: `light|medium|full|extreme`
- `performance_mode`: `lite|middle|hard|auto`
- `network_policy.web_probe_allowed`: разрешить HTTP probing (по умолчанию `false` в лёгких режимах)

### `limits`

- `max_reports`: сколько отчётов хранить
- `max_run_seconds`: лимит времени на запуск (best-effort)
- `max_files_per_collector`: ограничение на количество файлов

### `exports`

- `default_redaction_level`: `strict|normal|off`

### `allowlist`

- `apps`: список разрешённых приложений по `app_id`.

Пример:

```json
{
  "server": {"enabled": true, "bind": "0.0.0.0", "port": 8080, "token": "..."},
  "modes": {
    "research_mode": "medium",
    "performance_mode": "auto",
    "network_policy": {"web_probe_allowed": false}
  },
  "exports": {"default_redaction_level": "strict"},
  "allowlist": {"apps": [{"app_id": "xray-core"}]}
}
```
