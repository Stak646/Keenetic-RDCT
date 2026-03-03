# RDCT — Router Diagnostic & Control Tool (USB-only)

Это реализация **MVP-инструмента** по ТЗ RDCT (KeeneticOS + Entware, USB-only, CLI + WebUI/API, снапшоты, манифест, инкрементальность и Policy Engine).  
Полный исходник — в каталоге `rdct/`.

## Ключевые принципы (реализовано)

- **USB-only**: все директории RDCT (install/deps/cache/run/reports/logs) обязаны быть на внешнем носителе. Если нет USB — запуск запрещён.
- **Снапшот**: каждый запуск формирует каталог `snapshot/` с `manifest.json`, логами коллекторов, отчётами и `checksums.sha256`, и создаёт архив `tar.gz`.
- **Режимы**: `light|medium|full|extreme` + `lite|middle|hard|auto` (часть ограничений применяется).
- **Инкрементальность**: baseline/delta, хранение индекса в `cache/`, генерация `diff/diff_report.json`.
- **Policy Engine**: загружает 80 правил (как в "Adaptive triggers") и умеет *машинно* оценивать часть из них (остальные остаются документированными в правилах и могут быть расширены).
- **WebUI/API**: встроенный HTTP-сервер со статическим UI и JSON API, защита токеном.

## Структура на USB

Укажите базовую папку на USB, например:

`/tmp/mnt/sda1/rdct`

Тогда RDCT использует:

- `deps/` — зависимости (пока без внешних pip-зависимостей; есть задел под opkg)
- `cache/` — индекс baseline/delta (`cache/index.json`, `cache/runs/*.normalized.json`)
- `run/` — временная staging зона текущего запуска
- `reports/<run_id>/snapshot/` — готовый снапшот
- `reports/<run_id>/<run_id>.tar.gz` — архив снапшота
- `logs/tool/rdct.log` — лог инструмента

## Быстрый старт (CLI)

### Установка с GitHub одной командой (рекомендуется, автозапуск WebUI)

Запусти **одну команду** на роутере (скрипт скачает RDCT на USB и создаст `rdct.sh` в базовой папке):

```sh
curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | \
  RDCT_GH_OWNER=<OWNER> RDCT_GH_REPO=<REPO> sh
```

Опционально:

- явно указать путь на USB:

```sh
curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | \
  RDCT_GH_OWNER=<OWNER> RDCT_GH_REPO=<REPO> RDCT_BASE=/tmp/mnt/sda1/rdct sh
```

После установки WebUI/API **запускается автоматически**.

Управление:

- Отключить автозапуск: `RDCT_NO_RUN=1`
- Запустить WebUI в foreground (команда не завершается): `RDCT_DAEMON=0`

### Запуск напрямую (для разработки / локально)

> На роутере нужен Python 3 (обычно в Entware: `/opt/bin/python3`).

```sh
python3 -m rdct --base /tmp/mnt/sda1/rdct init
python3 -m rdct --base /tmp/mnt/sda1/rdct preflight
python3 -m rdct --base /tmp/mnt/sda1/rdct run --mode light
python3 -m rdct --base /tmp/mnt/sda1/rdct reports
```

## WebUI/API

1) Включите сервер в конфиге (`config/rdct.json`) или запустите напрямую:

```sh
python3 -m rdct --base /tmp/mnt/sda1/rdct serve --bind 0.0.0.0 --port 8080
```

2) Откройте `http://<router-ip>:<port>/`  
3) Возьмите токен из `config/rdct.json` (`server.token`) и вставьте в WebUI.

## Выходные форматы

- `manifest.json` — единая точка входа в снапшот
- `logs/collectors/<collector_id>/result.json` — результат каждого коллектора
- `diff/diff_report.json` — diff baseline vs target (если baseline есть)
- `checksums.sha256` — контрольные суммы файлов снапшота

Подробнее: `docs/FORMAT_SPEC.md`

## Языки

- Документация доступна на **EN/RU** (`docs/*.md` и `docs/*.ru.md`).
- CLI поддерживает `--lang en|ru` (также автоопределение по `LANG` / `RDCT_LANG`).

## Что можно расширить дальше

- Углублённые коллекторы (wifi/qos/vpn/firewall/UPnP и т.д.)
- Более строгая реализация всех 80 adaptive правил (с условиями и автоматическими действиями)
- Экспорт "support bundle" с редактированием/маскированием и выбором содержимого
- Allowlist AppManager (install/update/rollback/uninstall) под вашу модель распространения

См. `docs/ARCHITECTURE.md` и `docs/COLLECTORS_CATALOG.md`.
