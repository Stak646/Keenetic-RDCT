# CLI Reference

## Global Options
- `--lang ru|en` — Language
- `--json` — JSON output
- `--verbose` — Detailed output
- `--quiet` — Minimal output
- `--version` — Show version

## Commands
| Command | Description |
|---|---|
| `start [--mode M] [--perf P]` | Start collection |
| `preflight` | Run preflight only |
| `report list` | List reports |
| `report download <id>` | Show archive path + SHA256 |
| `report delete <id>` | Delete report (dangerous_ops) |
| `report redaction <id>` | Show redaction report |
| `config show [--redact]` | Show effective config |
| `config validate` | Validate config.json |
| `config set <path> <value>` | Set config value |
| `checks show` | Show checks summary |
| `inventory show` | Show inventory |
| `chain show` | Show baseline/delta chain |
| `chain rebase` | Rebase chain (dangerous_ops) |
| `chain compact` | Compact chain (dangerous_ops) |
| `chain reset` | Reset StateDB (dangerous_ops) |
| `app status` | List services |
| `app start/stop/restart <n>` | Control service (dangerous_ops) |
| `sanitize <id>` | Create sanitized export |
| `update check/apply/rollback` | Manage updates |
| `collectors list` | List available collectors |
| `collectors describe <id>` | Show collector details |

## Exit Codes
- 0: Success
- 1: Error (env/resource)
- 2: Error (config/usage)
