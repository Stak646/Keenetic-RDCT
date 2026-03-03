# Быстрый старт

## 1) Установка

См. `docs/INSTALL.ru.md`.

## 2) Preflight

```sh
/tmp/mnt/sda1/rdct/rdct.sh preflight
```

Если preflight не проходит — RDCT **откажется** запускаться (USB-only строго обязателен).

## 3) Запуск сборки

```sh
/tmp/mnt/sda1/rdct/rdct.sh run --mode light
```

Режимы:

- `light` — самый быстрый, минимум данных, web probes выключены
- `medium` — больше сетевой/приложенческой диагностики
- `full` — включает тяжёлые коллекторы (FS/зеркало)
- `extreme` — максимум глубины (но всё равно с safety gates)

## 4) WebUI

```sh
/tmp/mnt/sda1/rdct/rdct.sh serve --bind 0.0.0.0 --port 8080
```

Открыть:

- `http://<router-ip>:8080/`

Токен:

- `<base>/config/rdct.json` → `server.token`

## 5) Redacted export

Перед отправкой в поддержку включай строгую редакцию:

```sh
/tmp/mnt/sda1/rdct/rdct.sh export --run-id <RUN_ID> --level strict
```

Экспорт будет в:

- `<base>/reports/<RUN_ID>/exports/`
