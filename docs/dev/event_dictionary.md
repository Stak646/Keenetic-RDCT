# Event Dictionary — Словарь событий event log

## Обязательные event_id

| event_id | module | Описание |
|---|---|---|
| `run.start` | core | Начало run |
| `run.finish` | core | Завершение run |
| `preflight.start` | preflight | Начало preflight |
| `preflight.finish` | preflight | Завершение preflight |
| `plan.built` | preflight | План сформирован |
| `collector.start` | core | Запуск collector |
| `collector.finish` | core | Завершение collector |
| `collector.timeout` | core | Таймаут collector |
| `collector.budget_skip` | core | Пропуск из-за бюджета Governor |
| `governor.throttle` | governor | Дросселирование |
| `governor.enospc` | governor | Критически мало места |
| `packager.start` | core | Начало упаковки |
| `packager.finish` | core | Завершение упаковки |
| `webui.start` | webui | Запуск WebUI |
| `webui.stop` | webui | Остановка WebUI |
| `watchdog.timeout` | core | Глобальный таймаут |
| `signal_received` | core | Получен сигнал (TERM/INT) |
| `graceful_shutdown` | core | Мягкая остановка |
| `config_invalid` | core | Невалидный config |
| `config_conflict` | core | Конфликт параметров config |
| `lock_failed` | core | Не удалось получить lock |
| `tmp_cleanup` | core | Очистка tmp |
| `mode_warning` | core | Предупреждение Full/Extreme |
| `bind_exposure` | preflight | WebUI bind не localhost |
| `usb_required` | preflight | USB не найден при usb_only |
| `retention_cleanup` | storage | Удаление старых snapshot |
| `unsafe_query_blocked` | adapter | Заблокирован unsafe запрос в readonly |

## Формат

Все события следуют схеме `event_log_entry.schema.json`:
```json
{"ts":"...","level":"...","module":"...","event_id":"...","message_key":"...","params":{...},"correlation_id":"...","duration_ms":...}
```
