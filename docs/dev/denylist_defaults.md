# Default Denylist — Step 319

Дефолтный denylist для зеркалирования (`policies/denylist.default.json`).

## Обязательные записи (всегда включены)

| Pattern | Причина |
|---|---|
| `/opt/keenetic-debug/run/*` | workdir (предотвращение рекурсии) |
| `/opt/keenetic-debug/var/*` | runtime data |
| `/opt/keenetic-debug/tmp/*` | temp files |
| `*.tar.gz` | готовые архивы |
| `*.zip` | готовые архивы |
| `/proc/*` | pseudo-fs (бесконечная глубина) |
| `/sys/*` | pseudo-fs |
| `/dev/*` | device nodes |
| `/tmp/*` | системный temp |
| `/var/tmp/*` | системный temp |

## Пользовательские дополнения

Файл `policies/denylist.json` может содержать дополнительные правила.
При обновлении продукта: merge (user rules сохраняются, новые default добавляются).

## Переопределение

Config `mirror.allowlist` может разрешить отдельные пути из denylist,
но **НЕЛЬЗЯ** разрешить: workdir, output_dir, архивы, /proc, /sys.
