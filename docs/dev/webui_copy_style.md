# WebUI Copy Style Guide

## Принципы
- Все строки через i18n (message_key → ru.json/en.json)
- Нет смешения языков на одном экране
- Технические ID (хэши, пути, report_id) — без перевода
- Предупреждения безопасности — всегда на обоих языках

## Тон
- RU: формальный, но не канцелярит. «Запуск диагностики» а не «Инициация процедуры»
- EN: clear, concise. "Start diagnostic" not "Initiate diagnostic procedure"

## Примеры пар RU/EN
| Ключ | RU | EN |
|---|---|---|
| `btn.start` | Запустить | Start |
| `status.running` | Выполняется… | Running… |
| `warn.dangerous_ops` | Опасные операции включены | Dangerous operations enabled |
| `error.no_disk_space` | Недостаточно свободного места | Insufficient disk space |
| `label.research_mode` | Режим исследования | Research mode |

## Безопасность
- Предупреждения о `dangerous_ops`, `0.0.0.0 bind`, роли — обязательны на обоих языках
- «remediation_hint» в checks — переводится через i18n
