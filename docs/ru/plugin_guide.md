# Руководство по созданию сборщика

## Структура

Каждый сборщик в `collectors/<id>/`:
- `plugin.json` — метаданные, зависимости, лимиты
- `run.sh` — исполняемый скрипт сбора

## Обязательные поля plugin.json

| Поле | Тип | Описание |
|---|---|---|
| `id` | string | Стабильный ID (напр. `system.base`) |
| `name` | string | Человекочитаемое имя |
| `version` | string | Версия (SemVer) |
| `contract_version` | int | Версия контракта framework |
| `requires_root` | bool | Требует root |
| `dangerous` | bool | Модифицирует систему |
| `dependencies` | object | Зависимости (команды, файлы) |
| `estimated_cost` | object | Оценка стоимости |
| `timeout_s` | int | Максимальное время |
| `max_output_mb` | int | Макс. размер выхода |
| `privacy_tags` | array | Типы чувствительных данных |

## Создание нового сборщика

```shell
scripts/new_collector.sh wifi.scan wifi
```

## Контракт выхода

1. Артефакты → `$COLLECTOR_WORKDIR/artifacts/`
2. result.json → `$COLLECTOR_WORKDIR/result.json`
3. Exit codes: 0=OK, 1=SOFT_FAIL, 2=HARD_FAIL

## Чек-лист CI

- [ ] plugin.json валиден
- [ ] version SemVer, contract_version число
- [ ] privacy_tags из словаря
- [ ] dependencies объявлены
- [ ] estimated_cost заполнен
- [ ] run.sh существует и исполняем
- [ ] В registry.json
