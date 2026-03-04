# CHECKLIST_HW.md — Целевые устройства для ручной проверки

## Минимальный набор

| # | Архитектура | Устройство (пример) | ОС | Entware | Статус |
|---|---|---|---|---|---|
| 1 | mipsel | Keenetic Viva (KN-1912) | KeeneticOS 4.x | да (USB) | ⬜ |
| 2 | mipsel | Keenetic City (KN-1511) | KeeneticOS 3.x | да (internal) | ⬜ |
| 3 | aarch64 | Keenetic Peak (KN-2710) | KeeneticOS 4.x | да (USB) | ⬜ |
| 4 | mips | Keenetic (старая модель) | KeeneticOS 3.x | нет | ⬜ |
| 5 | — | Sandbox (x86_64 VM) | Ubuntu + BusyBox | fixtures | ⬜ |

## Чек-лист проверки на каждом устройстве

- [ ] install.sh выполняется без ошибок
- [ ] WebUI стартует, порт выбирается автоматически
- [ ] CLI `tool --version` / `tool --help` работает (RU/EN)
- [ ] `tool start --mode light --perf lite` — snapshot создаётся
- [ ] Manifest валиден, sha256 совпадают
- [ ] Без Entware — graceful degradation (только base collectors)
- [ ] USB-only mode: отказ без USB, работа с USB
- [ ] ENOSPC: частичный snapshot при < 20MB free
- [ ] Самозеркалирование: CRITICAL при попытке включить workdir
