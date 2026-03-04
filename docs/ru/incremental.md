# Инкрементальные snapshot и цепочки

## Как это работает

1. **Baseline**: Полный сбор (chain_depth=0).
2. **Delta**: Инкрементальный сбор. Только изменённые данные.
3. **Chain**: Цепочка baseline + дельты. `chain_max_depth` ограничивает глубину.

## StateDB
- SQLite (WAL) при наличии, JSON fallback
- Хранит: индекс файлов, fingerprints команд, курсоры логов, inventory, метаданные цепочки

## Ребазирование
```shell
keenetic-debug chain rebase    # Требует dangerous_ops=true
```

## Checks
ChecksEngine сравнивает baseline vs текущее: новые порты, дрейф пакетов/конфигов, WiFi/VPN регрессии, рост хранилища, аномалии логов.
