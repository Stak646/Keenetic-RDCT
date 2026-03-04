# keenetic-debug

![CI](https://github.com/keenetic-debug/keenetic-debug/actions/workflows/ci.yml/badge.svg)
![License](https://img.shields.io/badge/license-MIT-blue)
![Version](https://img.shields.io/badge/version-0.1.0--alpha-orange)

Diagnostic tool for Keenetic routers with Entware.

## Quick Start

```shell
curl -fsSL https://github.com/Stak646/Keenetic-RDCT/install.sh | sh
keenetic-debug start --mode light --perf lite
```

## Features
- 21 data collectors (system, network, wifi, vpn, storage, apps, mirror)
- WebUI with auth, roles, rate limiting
- CLI with full RU/EN localization
- Incremental snapshots (baseline/delta chain)
- 10+ automated checks (port drift, config drift, WiFi/VPN regression, etc.)
- Privacy modes: Light (mask secrets) → Extreme (preserve all)
- Safe-by-default: localhost bind, bearer token, readonly mode

## Documentation
- [Quick Start EN](docs/en/quickstart.md) | [RU](docs/ru/quickstart.md)
- [Installation EN](docs/en/installation.md) | [RU](docs/ru/installation.md)
- [WebUI Guide EN](docs/en/webui_guide.md) | [RU](docs/ru/webui_guide.md)
- [CLI Reference EN](docs/en/cli_reference.md) | [RU](docs/ru/cli_reference.md)
- [Security & Privacy EN](docs/en/security_privacy.md) | [RU](docs/ru/security_privacy.md)
- [Configuration EN](docs/en/configuration.md) | [RU](docs/ru/configuration.md)
- [Plugin Guide EN](docs/en/plugin_guide.md) | [RU](docs/ru/plugin_guide.md)
- [Troubleshooting EN](docs/en/troubleshooting.md) | [RU](docs/ru/troubleshooting.md)

## Supported Architectures
- mipsel (most Keenetic routers)
- mips
- aarch64 (newer models)

## Security by Default
- WebUI binds to 127.0.0.1 only
- Bearer token authentication
- dangerous_ops=false by default
- Rate limiting on all API endpoints
- Automatic redaction in Light/Medium modes
