# Руководство по установке

## Быстрая установка (онлайн)

```shell
curl -fsSL https://github.com/keenetic-debug/releases/latest/download/install.sh | sh
```

Или через wget:
```shell
wget -qO- https://github.com/keenetic-debug/releases/latest/download/install.sh | sh
```

## Параметры

```shell
sh install.sh --prefix /opt/keenetic-debug --channel stable
sh install.sh --offline bundle.tar.gz
sh install.sh --upgrade
sh install.sh --uninstall --yes
sh install.sh --verify
sh install.sh --repair
sh install.sh --dry-run
sh install.sh --no-webui          # Только CLI
sh install.sh --no-autostart      # Без автозапуска
```

## Оффлайн-установка

1. Скачайте bundle для вашей архитектуры на ПК
2. Скопируйте на USB-накопитель
3. Установите: `sh install.sh --offline /mnt/usb/bundle.tar.gz`

## Обновление

```shell
sh install.sh --upgrade
keenetic-debug update rollback    # Откат
```

## Удаление

```shell
sh install.sh --uninstall --yes   # Удалить всё
sh install.sh --uninstall         # Сохранить отчёты
```

## Безопасность поставки

Все загрузки проверяются по SHA-256 из `release-manifest.json`.
При несовпадении хэша — установка прерывается.

## Токен авторизации

- Генерируется при установке: `var/.auth_token` (права: 0600)
- Просмотр: `cat /opt/keenetic-debug/var/.auth_token`
- Ротация: `keenetic-debug webui token rotate`
- Роли: `admin` (полный доступ), `readonly` (только просмотр)
