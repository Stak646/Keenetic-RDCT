# Troubleshooting / FAQ

## ENOSPC (No disk space)
- Use USB drive: `--usb-only` or `config.usb_only=true`
- Reduce mode: `--mode light --perf lite`

## OOM (Out of memory)
- Governor auto-reduces workers
- Use `--perf lite` for minimal resource usage

## No Entware
- Only base collectors run (system.base, network.base, config.keenetic_rci)
- WebUI requires Python3 (Entware); use CLI without it

## Port conflict
- Auto-discovery in range 5000-5099
- Override: `config.webui.port=5050`

## Permissions
- Some collectors need root; use `sudo` or run as root
- `requires_root=true` collectors SKIP without root

## Timeout/Watchdog
- Global timeout: 30 min default
- Per-collector: see plugin.json `timeout_s`
- Governor reduces workers under load
