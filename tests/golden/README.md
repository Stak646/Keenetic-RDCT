# Golden Snapshots

Эталонные snapshot'ы для регрессионного тестирования форматов.

Генерируются через `scripts/run_sandbox.sh` и фиксируются.
При изменении схем — обновлять golden snapshots.

## Структура
```
golden/
├── manifest.golden.json    # Эталонный manifest
├── structure.golden.txt    # Эталонная структура tar.gz
└── README.md
```
