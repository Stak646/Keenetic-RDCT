# Contributing / Правила участия

## Ветвление
- `main` — защищённая ветка, только через PR
- Feature branches: `feature/<short-name>`
- Bugfix branches: `fix/<short-name>`
- Release: tags `vX.Y.Z`

## Стиль коммитов
```
<type>(<scope>): <description>

Типы: feat, fix, docs, style, refactor, test, ci, chore
Scope: core, collector, webui, cli, installer, schema, i18n, docs
```

## Требования к PR

- [ ] Тесты проходят (`scripts/run_tests.sh`)
- [ ] Документация обновлена (RU + EN)
- [ ] Локализация: ключи добавлены в `i18n/ru.json` и `i18n/en.json`
- [ ] Security impact оценён
- [ ] Schema impact оценён (если затрагивает контракты)
- [ ] CHANGELOG.md обновлён

## Shell стиль

- POSIX-совместимый shell (ash)
- snake_case для переменных и функций
- Двойные кавычки вокруг переменных: `"$var"`
- `set -eu` в начале каждого скрипта
- Комментарии на английском в коде

## Локализация

- Все пользовательские строки через `message_key` + params
- Запрет жёстко вшитых строк на любом языке
- При добавлении ключа — обязательно в оба файла (ru/en)

## Обновление примеров и golden snapshots

Любые изменения API/схем/CLI **обязаны** сопровождаться:
- Обновлением `examples/` (config/artifacts examples)
- Обновлением `tests/golden/` (если меняются форматы артефактов)
- Обновлением документации RU/EN
