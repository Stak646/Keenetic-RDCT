# DESIGN_COLLECTORS.md — Каталог коллекторов, зеркалирование, редактирование

> Шаги 71–76 плана.

---

## 1. Каталог категорий collectors (Step 71)

| ID | Категория | Мин. режим | Root | Dangerous | Описание |
|---|---|---|---|---|---|
| `system.base` | Система | Light | нет | нет | CPU/RAM/uptime/ps/df/mount/dmesg |
| `system.kernel` | OS/Kernel | Medium | нет | нет | /proc/interrupts, modules, sysctl, temps |
| `network.base` | Сеть (базовый) | Light | нет | нет | ip/route/ss/iptables/resolv |
| `network.deep` | Сеть (глубокий) | Medium | нет | нет | conntrack/NAT/UPnP/ARP/ND/bridge/VLAN/QoS |
| `network.dns_dhcp` | DNS/DHCP | Medium | нет | нет | leases, resolver, upstream DNS |
| `wifi.radio` | Wi-Fi | Medium | нет | нет | каналы/DFS/клиенты/RSSI/airtime |
| `vpn.status` | VPN/Туннели | Medium | нет | нет | WG/OpenVPN/IPsec/L2TP peers/routes |
| `storage.fs` | Хранилище | Light | нет | нет | устройства/разделы/mount/inode/top-N |
| `storage.health` | SMART/здоровье | Full | нет | нет | SMART (если smartctl доступен) |
| `security.exposure` | Безопасность | Medium | нет | нет | порты+баннеры/firewall/certs/remote_access |
| `config.keenetic` | Конфиги KeeneticOS | Light | нет | нет | ndm/rcicli/http_rci конфиги |
| `config.entware` | Конфиги Entware | Light | нет | нет | /opt/etc/* конфиги приложений |
| `config.opkg` | Пакеты opkg | Light | нет | нет | status/installed/repo |
| `hooks.ndm` | Hooks ndm | Medium | нет | нет | ndm hooks + граф зависимостей |
| `services.initd` | Сервисы init.d | Light | нет | нет | /opt/etc/init.d файлы/состояние |
| `processes.extended` | Процессы (расш.) | Medium | нет | нет | дерево/FD/ресурсы/хэши бинарников |
| `scheduler.autostart` | Автозапуск | Medium | нет | нет | cron/ndm events/скрипты за пределами init.d |
| `logs.system` | Системные логи | Medium | нет | нет | syslog/dmesg хвосты (с cursor) |
| `logs.vpn` | VPN логи | Medium | нет | нет | логи VPN-сервисов (с cursor) |
| `telemetry.mini` | Мини-телеметрия | Full | нет | нет | 30-300 сек сэмплинг CPU/RAM/net/conntrack |
| `apps.inventory` | Инвентаризация apps | Medium | нет | нет | port→pid→pkg→config→endpoint |
| `apps.websnap` | Web-слепки | Full | нет | **да** | HTML+headers endpoint'ов (conditional req) |
| `apps.screenshot` | Скриншоты | Extreme | нет | **да** | wkhtmltoimage/chromium (если доступен) |
| `mirror.full` | Зеркалирование | Extreme | нет | нет | обход ФС с denylist/лимитами |
| `api.search` | Поиск API | Full | нет | нет | regex/эвристики в конфигах/скриптах |

---

## 2. Команды и Fallback'и по категориям (Step 72)

### system.base
| Команда/Файл | Обязательность | Fallback |
|---|---|---|
| `cat /proc/cpuinfo` | required | `/proc/version` |
| `cat /proc/meminfo` | required | `free` (если есть) |
| `cat /proc/loadavg` | required | — |
| `ps` | required | `ls /proc/[0-9]*` |
| `df -h` | required | `cat /proc/mounts` + `stat -f` |
| `mount` | required | `cat /proc/mounts` |
| `dmesg` | optional | `cat /var/log/dmesg` (если доступен) |
| `uptime` | optional | parse `/proc/uptime` |

### network.base
| Команда/Файл | Обязательность | Fallback |
|---|---|---|
| `ip addr` | required | `ifconfig` |
| `ip route` | required | `route` / `netstat -rn` |
| `ip rule` | optional | — |
| `ss -tulnp` | required | `netstat -tulnp` |
| `iptables -L -n -v` | optional | `iptables-save` |
| `cat /etc/resolv.conf` | required | `/tmp/resolv.conf` |
| `cat /proc/net/dev` | required | — |

### network.deep
| Команда/Файл | Обязательность | Fallback |
|---|---|---|
| `conntrack -L` | optional | `cat /proc/net/nf_conntrack` |
| `arp -a` | optional | `cat /proc/net/arp` / `ip neigh` |
| `brctl show` | optional | `bridge link` |
| `cat /proc/net/dev` | required | — |
| sysctl net.* (read) | optional | `cat /proc/sys/net/...` |

### wifi.radio
| Команда/Файл | Обязательность | Fallback |
|---|---|---|
| `iwinfo` | optional | `iwconfig` / `iw dev` |
| `iwinfo <dev> assoclist` | optional | `iw station dump` |
| `/sys/class/ieee80211/` | optional | — |

### vpn.status
| Команда/Файл | Обязательность | Fallback |
|---|---|---|
| `wg show` | optional | `/proc/wireguard/` |
| `cat /tmp/openvpn/status` | optional | `openvpn --status` via management |
| `ipsec statusall` | optional | `/proc/net/xfrm_*` |

### storage.fs
| Команда/Файл | Обязательность | Fallback |
|---|---|---|
| `blkid` | optional | `cat /proc/partitions` + mount |
| `df -i` | optional | — |
| `find` (top-N) | optional | `du -s` + `ls` |
| `cat /proc/mounts` | required | `mount` |

---

## 3. Стратегия зеркалирования (Step 73)

### 3.1. Алгоритм обхода

```
mirror_root = config.mirror.roots  # ["/opt", "/etc"] по умолчанию

for each root in mirror_root:
  walk(root, depth=0)

walk(path, depth):
  if path in denylist → log(excluded, reason=denylist) → skip
  if depth > max_depth → log(excluded, reason=depth_limit) → skip
  if is_symlink(path) and not follow_symlinks → log(excluded, reason=symlink) → skip
  if is_symlink(path) and resolve(path) in visited → log(excluded, reason=cycle) → skip
  if total_files >= max_files → log(excluded, reason=file_limit) → stop
  if total_size >= max_total_mb → log(excluded, reason=size_limit) → stop

  if is_dir(path):
    for entry in ls(path):
      walk(path/entry, depth+1)
  elif is_file(path):
    if file_size > max_file_mb → log(excluded, reason=file_too_large) → skip
    if extension in denylist_extensions → log(excluded, reason=extension) → skip
    copy_to_artifacts(path)
    total_files += 1
    total_size += file_size
    visited.add(resolve(path))
```

### 3.2. Самозеркалирование — обнаружение

**CRITICAL**: перед началом обхода и на КАЖДОМ шаге:

```
FORBIDDEN_PATHS = [
  workdir,           # tmp/<session>/
  output_dir,        # var/reports/
  INSTALL_DIR,       # /opt/keenetic-debug/
  *.tar.gz,          # архивы
  *.zip
]

if resolve(path).startswith(any(FORBIDDEN_PATHS)):
  log(CRITICAL, "self_mirror_detected", path=path)
  ABORT mirror collector → HARD_FAIL
```

### 3.3. Лимиты по умолчанию

| Лимит | Значение | Настраиваемый |
|---|---|---|
| `max_depth` | 10 | config.mirror.max_depth |
| `max_files` | 10000 | config.mirror.max_files |
| `max_total_mb` | 500 | config.mirror.max_total_mb |
| `max_file_mb` | 50 | config.mirror.max_file_mb |
| `follow_symlinks` | false | config.mirror.follow_symlinks |

---

## 4. Отчёт о пропущенных путях — excluded.json (Step 74)

```json
{
  "schema_id": "excluded",
  "schema_version": "1",
  "total_excluded": 42,
  "entries": [
    {
      "path": "/opt/var/log/large.log",
      "reason": "file_too_large",
      "rule_id": "mirror.max_file_mb",
      "size_hint": 128000000
    },
    {
      "path": "/opt/keenetic-debug/var/reports/",
      "reason": "self_mirror_denylist",
      "rule_id": "denylist.output_dir",
      "size_hint": null
    },
    {
      "path": "/opt/some/deep/nested/path",
      "reason": "depth_limit",
      "rule_id": "mirror.max_depth",
      "size_hint": null
    }
  ]
}
```

---

## 5. Интеграция Redaction (Steps 75–76)

### 5.1. Точка применения (Step 75)

Redaction выполняется **после** сбора всех артефактов, **до** упаковки:

```
execute collectors → собраны raw artifacts
         │
         ▼
RedactionEngine.process(artifacts, research_mode, privacy_policy)
         │
         ├── Сканирует каждый текстовый файл
         ├── Применяет правила из policies/privacy.json
         ├── Формирует redaction_report.json
         └── Заменяет/маскирует in-place (или создает .redacted копию)
         │
         ▼
Packager → упаковывает уже редактированные файлы
```

### 5.2. Форматы маскирования (Step 76)

| Privacy Tag | Light/Medium | Full | Extreme |
|---|---|---|---|
| `password` | `***REDACTED***` (zeroize) | as-is + flag | as-is + flag |
| `token` | `tok_****XXXX` (partial mask, последние 4) | as-is + flag | as-is + flag |
| `ip` | `192.168.XXX.XXX` (хеш последних октетов) | as-is + flag | as-is |
| `mac` | `AA:BB:CC:XX:XX:XX` (хеш последних 3) | as-is + flag | as-is |
| `ssid` | `SSID_<sha256[:8]>` (хеш) | as-is + flag | as-is |
| `cookie` | `***REDACTED***` (zeroize) | as-is + flag | as-is |
| `key` | `***REDACTED***` (zeroize) | as-is + flag | as-is + flag |
| `cert` | содержимое redacted, метаданные видны | as-is + flag | as-is |

### 5.3. Redaction Report

```json
{
  "schema_id": "redaction_report",
  "schema_version": "1",
  "research_mode": "medium",
  "total_findings": 23,
  "findings": [
    {
      "file": "collectors/config.entware/artifacts/nginx.conf",
      "line": 42,
      "tag": "password",
      "action": "zeroize",
      "context": "server_password = ***REDACTED***"
    }
  ],
  "summary": {
    "password": 5,
    "token": 3,
    "ip": 12,
    "mac": 3,
    "ssid": 0,
    "cookie": 0,
    "key": 0,
    "cert": 0
  }
}
```

---

## 6. Обязательные артефакты snapshot'а (Step 77)

Вне зависимости от режима, snapshot **обязан** содержать:

| Артефакт | Описание | Создаётся |
|---|---|---|
| `manifest.json` | Описатель содержимого, sha256, размеры | Packager |
| `preflight.json` | Результат preflight | Preflight |
| `plan.json` | План выполнения | Preflight |
| `event_log.jsonl` | Структурированный лог событий | Logger |
| `debugger_report.json` | Аварийный отчёт / диагностика | Debugger |
| `redaction_report.json` | Отчёт о чувствительных данных | RedactionEngine |

Даже при CRASH / partial failure — Debugger формирует минимальный отчёт.

## Нормализация команд (Step 587)
Framework предоставляет нормализатор для вывода команд: удаление timestamps, counters, volatile data перед хэшированием для incremental стратегии.

## Raw vs Redacted (Step 627)
В Full/Extreme: framework сохраняет «raw» артефакты опционально (при включении).
В Light/Medium: только redacted версии.
