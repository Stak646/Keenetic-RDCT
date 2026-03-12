# Keenetic-RDCT

Диагностический инструмент для роутеров Keenetic с Entware.

## Установка

```bash
curl -fsSL https://raw.githubusercontent.com/Stak646/Keenetic-RDCT/main/scripts/install.sh | sh
```

Или через wget:
```bash
wget -qO- https://raw.githubusercontent.com/Stak646/Keenetic-RDCT/main/scripts/install.sh | sh
```

После установки вы увидите:
```
  ✅  Keenetic-RDCT установлен!

  WebUI:  http://192.168.1.1:5000
  Токен:  a1b2c3d4e5f6...

  Откройте WebUI в браузере и используйте токен для входа.
```

## Требования

- Keenetic с Entware
- python3-light (`opkg install python3-light`) — для WebUI
- Архитектуры: mipsel, mips, aarch64

## Использование

### WebUI
Откройте `http://<IP роутера>:<порт>` и введите токен.

### CLI
```bash
/opt/keenetic-debug/cli/keenetic-debug --help
/opt/keenetic-debug/cli/keenetic-debug start --mode light --perf lite
/opt/keenetic-debug/cli/keenetic-debug report list
```

### Управление сервисом
```bash
/opt/etc/init.d/S99keeneticrdct start
/opt/etc/init.d/S99keeneticrdct stop
/opt/etc/init.d/S99keeneticrdct status
```

## Безопасность

- WebUI слушает на `0.0.0.0` (LAN) с Bearer Token аутентификацией
- Токен в `var/.auth_token` (chmod 600)
- dangerous_ops отключён по умолчанию
- Режимы приватности: Light (маскирование) → Extreme (всё как есть)

## Документация

- [Quick Start RU](docs/ru/quickstart.md) | [EN](docs/en/quickstart.md)
- [Установка](docs/ru/installation.md) | [Installation](docs/en/installation.md)
- [WebUI](docs/ru/webui_guide.md) | [WebUI Guide](docs/en/webui_guide.md)
- [CLI](docs/ru/cli_reference.md) | [CLI Reference](docs/en/cli_reference.md)
- [Безопасность](docs/ru/security_privacy.md) | [Security](docs/en/security_privacy.md)
- [Конфигурация](docs/ru/configuration.md) | [Configuration](docs/en/configuration.md)
- [Устранение неполадок](docs/ru/troubleshooting.md) | [Troubleshooting](docs/en/troubleshooting.md)

## Удаление

```bash
/opt/etc/init.d/S99keeneticrdct stop
rm -rf /opt/keenetic-debug /opt/etc/init.d/S99keeneticrdct
```
