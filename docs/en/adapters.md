# Adapters

## Supported Adapters
- **ndm** (default): KeeneticOS native management daemon
- **rcicli**: RCI command-line interface
- **http_rci**: HTTP-based RCI (disabled by default)
- **ssh**: SSH access (disabled by default, requires explicit enable)

## Security
- Only read-only queries in readonly mode
- Safe query whitelist enforced
- All requests logged in audit trail
- ssh disabled by default (Step 335)
