# App Manager (Allowlist приложения)

В RDCT предусмотрена концепция **App Manager по allowlist**:

- распознаёт известные приложения (по процессам/портам/путям конфигов)
- собирает **app-specific debug bundle** в отчёте
- опционально умеет помогать с установкой/обновлением allowlist-приложений (через GitHub releases)

## Безопасность

- Поддерживаются только allowlist-приложения
- Установка идёт в `<base>/apps/<app_id>/...` на USB
- Автостарт по умолчанию не делается; start/stop — только по явной команде пользователя

## Каталог приложений

См. `rdct/apps/catalog.json`.

## CLI

```sh
/tmp/mnt/sda1/rdct/rdct.sh apps list
/tmp/mnt/sda1/rdct/rdct.sh apps status
/tmp/mnt/sda1/rdct/rdct.sh apps install <app_id>
/tmp/mnt/sda1/rdct/rdct.sh apps update <app_id>
```

> Установка/обновление требуют интернет.
