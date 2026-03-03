# Установка

RDCT рассчитан на **KeeneticOS + Entware** и хранит **все** данные только на внешнем USB-накопителе (USB-only).

## Установка с GitHub одной командой (автозапуск WebUI)

Запусти на роутере:

```sh
curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | \
  RDCT_GH_OWNER=<OWNER> RDCT_GH_REPO=<REPO> sh
```

Опционально:

- Явно указать путь на USB:

```sh
curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | \
  RDCT_GH_OWNER=<OWNER> RDCT_GH_REPO=<REPO> RDCT_BASE=/tmp/mnt/sda1/rdct sh
```

Что делает скрипт:

- Находит внешний USB-mount по `/proc/mounts`
- Создаёт структуру каталогов RDCT на USB
- Скачивает репозиторий (или release-asset, если есть) в `<base>/install`
- Создаёт обёртку `<base>/rdct.sh` (для запуска без `cd`)
- Инициализирует `config/rdct.json`

После установки скрипт **автоматически запускает WebUI/API**.

По умолчанию:

- WebUI стартует **в фоне** (команда завершается)
- Логи: `<base>/logs/rdct-serve.log`

Управление:

- Отключить автозапуск: `RDCT_NO_RUN=1`
- Запустить WebUI в foreground (команда не завершается): `RDCT_DAEMON=0`

## Ручная установка (git clone)

Если удобнее через `git`:

```sh
git clone https://github.com/<OWNER>/<REPO>.git
cd <REPO>
RDCT_GH_OWNER=<OWNER> RDCT_GH_REPO=<REPO> sh ./install.sh
```

## Требования

- Внешний USB-накопитель смонтирован в режиме read-write
- `python3` (рекомендуется поставить через Entware)
- `curl` или `wget`, и `tar`

Установщик может **опционально** поставить `python3` через `opkg` (Entware), если его нет.

## Обновление

Просто запусти установщик ещё раз. Он перекачает инструмент в `<base>/install` и пересоздаст `<base>/rdct.sh`.

## Удаление

Удаление — это удаление папки на USB:

```sh
rm -rf /tmp/mnt/sda1/rdct
```

> RDCT не пишет ничего во внутреннее хранилище KeeneticOS.
