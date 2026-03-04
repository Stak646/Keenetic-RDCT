# Configuration Priority — Порядок приоритетов

## Цепочка приоритетов (от высшего к низшему)

```
1. CLI flags         --mode, --perf, --lang, --debug
2. Environment       KEENETIC_DEBUG_MODE, KEENETIC_DEBUG_LANG, TOOL_LANG
3. config.json       /opt/keenetic-debug/config.json
4. Built-in defaults (из config.schema.json)
```

## Правила

- Каждое значение помечено источником: `cli`, `env`, `config`, `default`
- `tool config show` отображает effective config с пометкой источника
- `tool config show --redact` маскирует токены/пароли для Light/Medium
- `tool config export` = `config show --redact` для передачи в поддержку

## Пример

```json
{
  "research_mode": {"value": "light", "source": "cli"},
  "performance_mode": {"value": "auto", "source": "config"},
  "lang": {"value": "ru", "source": "env"},
  "debug": {"value": false, "source": "default"}
}
```
