# Каталог коллекторов (MVP)

Коллекторы — это модули, которые собирают данные и пишут результат в:

`snapshot/logs/collectors/<collector_id>/result.json`

и артефакты — в соответствующие каталоги внутри `snapshot/`.

## MVP (базовые)

- device/environment/storage
- processes/ports/routes
- dmesg
- entware/opkg
- summary/checksums

## EXT (расширенные, включаются политикой/режимом)

- firewall (iptables/nft)
- dns/dhcp
- wifi/vpn
- file-security (SUID/SGID/world-writable)
- recent-changes/large-files
- app-inventory + debug bundle
- web-snapshot + js-api-extractor
- sandbox-tests

Примечания:

- В лёгких режимах часть EXT отключена (cost/risk).
- Политика (`policy/rules.json`) может включать/отключать коллекторы автоматически.
