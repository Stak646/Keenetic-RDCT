# Security Model / Модель безопасности

## Принципы

- **Least Privilege**: Core/WebUI/CLI работают с минимальными правами
- **Safe-by-Default**: readonly=true, dangerous_ops=false, bind=127.0.0.1
- **Defense in Depth**: bearer auth + CSRF + rate limiting + bind restriction

## WebUI Security

- Bind: `127.0.0.1` (по умолчанию) или LAN адрес (по конфигу)
- Запрет `0.0.0.0`
- Bearer token: генерируется при установке, хранится в `run/auth.token`
- Роли: `readonly` (GET), `admin` (GET + POST/DELETE)
- CSRF: если cookies → CSRF token + SameSite; если bearer → origin check
- Rate limiting: 120 rpm API, 10 rpm тяжёлые операции
- Автопоиск порта: 5000-5099

## Опасные операции

Требуют `dangerous_ops=true` + роль `admin`:
- restart/restore/modify config сервисов
- Активные HTTP-запросы к эндпоинтам
- Удаление snapshot'ов
- Глубокие сканы (full mirror)

## Приватность

- Light/Medium: маскирование PII (password, token, IP, MAC, SSID, cookie, key)
- Full/Extreme: сохранение as-is + обязательный redaction report
- Пользовательские правила: regex/allowlist/denylist
