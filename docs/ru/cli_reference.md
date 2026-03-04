# Справочник CLI

## Глобальные параметры
- `--lang ru|en` — Язык
- `--json` — Вывод JSON
- `--verbose` — Подробный вывод
- `--version` — Версия

## Команды
| Команда | Описание |
|---|---|
| `start [--mode M] [--perf P]` | Запуск сбора |
| `preflight` | Только preflight |
| `report list` | Список отчётов |
| `report download <id>` | Путь к архиву + SHA256 |
| `report delete <id>` | Удалить (dangerous_ops) |
| `config show [--redact]` | Показать конфигурацию |
| `config validate` | Валидация config.json |
| `checks show` | Показать проверки |
| `inventory show` | Показать инвентаризацию |
| `chain show` | Показать цепочку |
| `chain rebase` | Ребазирование (dangerous_ops) |
| `sanitize <id>` | Экспорт для поддержки |
| `app status` | Список сервисов |
| `collectors list` | Список сборщиков |
