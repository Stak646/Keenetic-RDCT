# Устранение неполадок / FAQ

## ENOSPC (нет места)
- Используйте USB: `config.usb_only=true`
- Уменьшите режим: `--mode light --perf lite`

## OOM (нехватка памяти)
- Governor снижает число воркеров
- Используйте `--perf lite`

## Нет Entware
- Работают только базовые сборщики
- WebUI требует Python3; без Entware используйте CLI

## Конфликт портов
- Автопоиск в диапазоне 5000-5099
- Переопределение: `config.webui.port=5050`

## Таймаут
- Глобальный: 30 мин
- Per-collector: plugin.json `timeout_s`
