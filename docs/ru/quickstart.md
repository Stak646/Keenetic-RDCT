# Быстрый старт

## Установка
```shell
curl -fsSL https://raw.githubusercontent.com/Stak646/Keenetic-RDCT/main/scripts/install.sh | sh
```

## Базовый snapshot
```shell
keenetic-debug start --mode light --perf lite
```

## Инкрементальный snapshot
```shell
keenetic-debug start --mode medium --perf auto --snapshot-mode delta
```

## Скачать отчёт
```shell
keenetic-debug report list
keenetic-debug report download <report_id>
```

## Очистить для передачи
```shell
keenetic-debug sanitize <report_id>
```
