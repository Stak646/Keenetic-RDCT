# Test Fixtures

## sandbox/
Минимальный набор фикстур файловой системы для offline-тестирования:
- `proc/` — /proc заглушки (cpuinfo, meminfo, loadavg)
- `opt/etc/init.d/` — init.d заглушки
- `opt/bin/` — opkg заглушка

## Использование
```shell
scripts/run_sandbox.sh
```
