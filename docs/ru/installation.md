# Установка / Обновление / Удаление

## Требования
- Keenetic с Entware (opkg, /opt)
- python3 (устанавливается автоматически)
- Архитектуры: mipsel, mips, aarch64
- Свободное место: от 10 МБ

## Онлайн установка
```bash
curl -fsSL https://raw.githubusercontent.com/Stak646/Keenetic-RDCT/main/scripts/install.sh -o /tmp/install.sh && sh /tmp/install.sh
```

Установщик автоматически:
1. Определяет архитектуру и наличие Entware
2. Устанавливает python3 (если отсутствует)
3. Скачивает проект с GitHub
4. Генерирует токен авторизации
5. Создаёт конфигурацию
6. Запускает WebUI на свободном порту

## Обновление
Запустите установщик и выберите пункт 2 (Обновить).

## Удаление
Запустите установщик и выберите пункт 3 (Удалить).

## Управление сервисом
```bash
/opt/etc/init.d/S99keeneticrdct start
/opt/etc/init.d/S99keeneticrdct stop
/opt/etc/init.d/S99keeneticrdct restart
/opt/etc/init.d/S99keeneticrdct status
```
