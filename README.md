# Keenetic-RDCT

🇷🇺 [Русская версия](#установка) | 🇬🇧 [English version](#installation)

Инструмент полной диагностики роутеров Keenetic с Entware.
Full diagnostic tool for Keenetic routers with Entware.

---

## Установка

```bash
# Онлайн установка (рекомендуется)
curl -fsSL https://raw.githubusercontent.com/Stak646/Keenetic-RDCT/main/scripts/install.sh -o /tmp/install.sh && sh /tmp/install.sh

# Или через wget
wget -qO /tmp/install.sh https://raw.githubusercontent.com/Stak646/Keenetic-RDCT/main/scripts/install.sh && sh /tmp/install.sh
```

### Требования
- Keenetic с Entware (opkg)
- Архитектуры: mipsel, mips, aarch64
- python3 (устанавливается автоматически)

### После установки
```
  ✅  Keenetic-RDCT установлен!

  WebUI:  http://192.168.1.1:5000
  Токен:  <ваш_токен>
```

Откройте WebUI в браузере и введите токен.

---

## Installation

```bash
# Online install (recommended)
curl -fsSL https://raw.githubusercontent.com/Stak646/Keenetic-RDCT/main/scripts/install.sh -o /tmp/install.sh && sh /tmp/install.sh

# Or via wget
wget -qO /tmp/install.sh https://raw.githubusercontent.com/Stak646/Keenetic-RDCT/main/scripts/install.sh && sh /tmp/install.sh
```

### Requirements
- Keenetic router with Entware (opkg)
- Architectures: mipsel, mips, aarch64
- python3 (installed automatically)

---

## Возможности / Features

### 🔍 27 коллекторов / 27 Collectors
| Категория / Category | Коллекторы / Collectors |
|---|---|
| Система / System | system.base, system.kernel, system.proc_snapshot, system.system_info |
| Сеть / Network | network.base, network.sockets, network.firewall, network.conntrack, network.dhcp_dns, network.interfaces, network.neighbors |
| WiFi | wifi.radio, wifi.clients |
| VPN | vpn.tunnels |
| Конфигурация / Config | config.entware, config.keenetic_rci, keenetic.rci_extended |
| Хранилище / Storage | storage.map, storage.topn |
| Безопасность / Security | security.exposure |
| Сервисы / Services | services.entware, hooks.ndm, scheduler.autostart |
| Приложения / Apps | apps.websnap, opkg.status |
| Зеркало / Mirror | mirror.full |
| Логи / Logs | logs.system |

### 🛡️ Менеджер приложений / App Manager
Установка, удаление, запуск/остановка:
- NFQWS Keenetic / NFQWS2 Keenetic
- NFQWS Keenetic Web
- HydraRoute Neo
- MagiTrickle
- AWG Manager

### 📊 WebUI (10 страниц / 10 pages)
- Панель / Dashboard — статус, запуск сбора
- Preflight — проверка окружения
- Прогресс / Progress — реалтайм прогресс
- Отчёты / Reports — список, скачивание, удаление
- Инвентаризация / Inventory — порт→процесс→пакет
- Проверки / Checks — аномалии и предупреждения
- Цепочка / Chain — baseline/delta визуализация
- Устройство / Device — модель, прошивка, RAM, CPU, температура
- Приложения / Apps — менеджер приложений
- Настройки / Settings — конфигуратор с формой

### 🔒 Безопасность / Security
- Bearer Token аутентификация
- Роли: admin / readonly
- Формат архива: tar.gz или zip (настраивается)
- Режимы приватности: Light→Extreme

---

## CLI

```bash
# Справка
/opt/keenetic-debug/cli/keenetic-debug --help

# Управление сервисом
/opt/etc/init.d/S99keeneticrdct start|stop|restart|status
```

---

## Удаление / Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/Stak646/Keenetic-RDCT/main/scripts/install.sh -o /tmp/install.sh && sh /tmp/install.sh
# Выберите пункт 3 / Choose option 3
```

Или вручную / Or manually:
```bash
/opt/etc/init.d/S99keeneticrdct stop
rm -rf /opt/keenetic-debug /opt/etc/init.d/S99keeneticrdct
```

---

## Лицензия / License

MIT
