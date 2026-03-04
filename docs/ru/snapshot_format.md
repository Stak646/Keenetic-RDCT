# Формат snapshot

## Структура архива

```
<report_id>.tar.gz
└── <report_id>/
    ├── manifest.json          # Индекс файлов с sha256
    ├── preflight.json         # Capabilities окружения
    ├── plan.json              # План выполнения
    ├── summary.json           # Итоги запуска
    ├── event_log.jsonl        # Лог событий (JSONL)
    ├── debugger_report.json   # Диагностика
    ├── redaction_report.json  # Отчёт о маскировании
    ├── inventory.json         # Карта порт→PID→пакет
    ├── collectors/            # Результаты сборщиков
    └── logs/                  # Контрольные точки
```

## Ключевые файлы

- **manifest.json**: Источник истины. Содержит path, size, sha256 для каждого файла.
- **redaction_report.json**: Что найдено и замаскировано (Light/Medium) или отмечено (Full/Extreme).
- **inventory.json**: Корреляция: порт → процесс → пакет → конфиг → endpoints.
