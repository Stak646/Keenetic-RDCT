# CLI Style Guide

## Формат help

```
Usage: keenetic-debug <command> [options]

Commands:
  start       Start diagnostic collection
  report      Manage reports (list/download/delete)
  ...

Options:
  --lang ru|en    Language (default: en)
  --json          Output in JSON format
  --quiet         Minimal output
  --verbose       Detailed output

Examples:
  keenetic-debug start --mode light --perf lite
  keenetic-debug report list
  keenetic-debug report download <id>
```

## Правила
- help: сначала usage, затем commands, затем examples
- Всегда неинтерактивный по умолчанию
- `--lang` приоритет: flag > config.lang > $LANG env > "en"
- Опасные команды: require `--confirm` при `--interactive`
- JSON output: `--json` для автоматизации
- Exit codes: 0=success, 1=error, 2=usage error

## Локализация
- `--help` полностью переведён на RU и EN
- Ошибки/предупреждения/summary — через i18n message_key
- Нет смешения языков в одном выводе
