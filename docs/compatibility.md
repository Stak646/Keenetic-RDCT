# Compatibility Matrix / Матрица совместимости

## Архитектуры

| Arch | uname -m | Статус | Примечания |
|------|----------|--------|------------|
| mipsel | mips (LE) | Поддерживается | Keenetic Giga, Ultra, Viva |
| mips | mips (BE) | Поддерживается | Старые модели |
| aarch64 | aarch64 | Поддерживается | Keenetic Peak, Hopper |

## Capabilities по коллекторам

| Collector | Команды | Файлы | Root | Entware |
|-----------|---------|-------|------|---------|
| system.base | cat, uname, ps, df, mount | /proc/* | Нет | Нет |
| network.base | ip (или ifconfig), ss (или netstat) | /proc/net/dev | Нет | Нет |
| network.deep | ip, ss, conntrack | /proc/net/* | Желательно | Да (conntrack) |
| wifi.radio | — | — | Нет | Нет |
| vpn.status | wg, openvpn | /opt/etc/openvpn | Нет | Да |
| storage.fs | df, du, mount | /proc/mounts | Нет | Нет |
| security.exposure | ss, iptables/nft | — | Желательно | Нет |
| config.keenetic | — (ndm/rci adapter) | — | Нет | Нет |
| config.entware | opkg, cat | /opt/etc/* | Нет | Да |
| mirror.full | find, cp | /opt | Нет | Да |

## Минимальные требования

- Shell: ash (BusyBox) или POSIX sh
- BusyBox: ≥ 1.30
- Entware: для расширенных collectors
- Python 3.8+: для WebUI (Entware python3)
- Свободное место: ≥50 MB на USB/внутренней памяти
