# Logging Conventions

## Форматы

### JSONL (event_log.jsonl) — машиночитаемый
```json
{"ts":"2026-03-04T14:30:22Z","level":"INFO","module":"core","event_id":"session_start","message_key":"app.session_started","params":{"report_id":"kn3010-..."},"correlation_id":"abc123","duration_ms":null}
```

### Human-readable (stdout/stderr) — сокращённый
```
2026-03-04T14:30:22Z [INFO] core: Session started (kn3010-...)
```

## Уровни

| Level | Когда | Примеры |
|---|---|---|
| DEBUG | Детальная диагностика (--verbose) | Variable values, paths |
| INFO | Нормальный ход | Session start, collector done, port selected |
| WARN | Нештатно, но продолжаем | Low disk, SOFT_FAIL, throttled |
| ERROR | Сбой компонента | HARD_FAIL, config invalid |
| CRITICAL | Аварийная остановка | ENOSPC, self-mirror, OOM kill |

## Поля JSONL

| Поле | Тип | Обязательное | Описание |
|---|---|---|---|
| `ts` | string (ISO 8601) | да | Timestamp |
| `level` | enum | да | DEBUG/INFO/WARN/ERROR/CRITICAL |
| `module` | string | да | core/preflight/governor/collector.xxx/webui/cli |
| `event_id` | string | да | Стабильный ID события (для фильтрации) |
| `message_key` | string | да | Ключ i18n |
| `params` | object | нет | Параметры для подстановки |
| `correlation_id` | string | нет | ID сессии/запуска |
| `duration_ms` | int | нет | Длительность операции |

## Правила
- Логи пишутся в `event_log.jsonl` (append-only)
- Audit log (`var/audit.log`) — только управленческие действия (start/stop/delete/restore)
- Уровень DEBUG — только при `config.debug=true` или `--verbose`
- message_key всегда через i18n (не хардкодить текст)
