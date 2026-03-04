# Security Policy / Политика безопасности

## Безопасные значения по умолчанию

- WebUI: bind `127.0.0.1`, bearer token auth, CSRF protection
- API: rate limiting, роли readonly/admin
- Core: `readonly=true`, `dangerous_ops=false`
- Redaction: маскирование PII в Light/Medium режимах
- Install: pinned sha256, проверка целостности

## Сообщение об уязвимостях / Reporting Vulnerabilities

Если вы обнаружили уязвимость безопасности, пожалуйста:

1. **НЕ** создавайте публичный Issue
2. Напишите на email: [security contact TBD]
3. Укажите: версию, шаги воспроизведения, потенциальный импакт

Мы стремимся ответить в течение 48 часов и выпустить патч в течение 7 дней для критических уязвимостей.

## Scope

В scope безопасности входят:
- WebUI API (аутентификация, авторизация, injection)
- CLI (privilege escalation, information disclosure)
- Installer (supply-chain, integrity verification)
- Collectors (information leakage, resource exhaustion)
- Redaction engine (bypass, incomplete masking)
