# Shell Style Guide — keenetic-debug

## Целевая совместимость
- **POSIX-ish ash** (BusyBox ≥1.30)
- Без bashisms: нет `[[`, нет arrays, нет `source` (используем `.`)
- Нет process substitution `<()`

## Правила
- Shebang: `#!/bin/sh` (не `#!/bin/bash`)
- Отступы: 2 пробела
- Переменные: `UPPER_CASE` для констант/env, `lower_case` для локальных
- Функции: `module_action()` (snake_case с префиксом модуля)
- Кавычки: всегда `"$var"` (double-quote переменные)
- Exit codes: 0=OK, 1=SOFT_FAIL, 2=HARD_FAIL, 124=TIMEOUT
- Проверка команд: `command -v <cmd> >/dev/null 2>&1`
- Временные файлы: `mktemp` или `$WORKDIR/tmp/`
- Cleanup: trap 'cleanup' EXIT INT TERM

## Запрещено
- `eval` (кроме исключительных случаев с обоснованием)
- Бинарные зависимости не из BusyBox/Entware
- Запись за пределами `$WORKDIR`
- Интерактивный ввод (кроме `--interactive` режима)
