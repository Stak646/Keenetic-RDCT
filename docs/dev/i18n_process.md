# i18n Process — Процесс локализации

## Структура
```
i18n/
├── ru.json    # Русский (полный набор ключей)
└── en.json    # English (полный набор ключей)
```

## Как добавить новую строку

1. Добавить ключ в **оба** файла (ru.json и en.json) одновременно
2. Ключ: `section.subsection.key_name` (dot-separated, snake_case)
3. Параметры: `{param_name}` в значении

Пример:
```json
// ru.json
"collector.timeout_exceeded": "Сборщик {collector_id} превысил таймаут ({timeout_s} сек)"

// en.json
"collector.timeout_exceeded": "Collector {collector_id} timed out ({timeout_s}s)"
```

## Проверка покрытия

```shell
scripts/check_l10n_coverage.sh
```

CI падает если:
- ru.json и en.json имеют разные наборы ключей
- Есть пустые значения
- Ключ используется в коде, но отсутствует в JSON

## Правила
- **Запрещено** частичное покрытие (один язык без другого)
- **Запрещено** хардкодить текст в коде — только через message_key
- **Исключения** из перевода: хэши, пути, report_id, технические ID
- **Приоритет языка**: `--lang` flag > `config.lang` > `$LANG` env > `"en"`
- Числа и даты: формат не зависит от языка (ISO 8601, десятичная точка)
