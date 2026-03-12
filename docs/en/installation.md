# Installation Guide

## Quick Install (Online)

```shell
curl -fsSL https://raw.githubusercontent.com/Stak646/Keenetic-RDCT/main/scripts/install.sh | sh
```

Or with wget:
```shell
wget -qO- https://raw.githubusercontent.com/Stak646/Keenetic-RDCT/main/scripts/install.sh | sh
```

## Options

```shell
sh install.sh --prefix /opt/keenetic-debug --channel stable
sh install.sh --offline bundle.tar.gz
sh install.sh --upgrade
sh install.sh --uninstall --yes
sh install.sh --verify
sh install.sh --repair
sh install.sh --dry-run
sh install.sh --no-webui          # CLI only
sh install.sh --no-autostart      # No init.d service
sh install.sh --print-config-default
```

## Offline Bundle

1. Download bundle for your architecture on a PC:
   - `keenetic-debug-X.Y.Z-offline-mipsel.tar.gz`
   - `keenetic-debug-X.Y.Z-offline-aarch64.tar.gz`
2. Copy to USB drive
3. Install: `sh install.sh --offline /mnt/usb/keenetic-debug-X.Y.Z-offline-mipsel.tar.gz`

## Upgrade

```shell
sh install.sh --upgrade
# or offline:
sh install.sh --upgrade --offline bundle.tar.gz
```

Previous version is backed up to `var/backup/`.

## Rollback

```shell
keenetic-debug update rollback
```

## Uninstall

```shell
sh install.sh --uninstall --yes          # Remove everything
sh install.sh --uninstall                # Keep reports for debugging
```

## Supply-Chain Security

All downloads are verified against pinned SHA-256 checksums from `release-manifest.json`.

- If hash mismatch: install fails immediately with clear error
- Manual verification: `sha256sum <file>` and compare with manifest
- Offline bundle includes its own SHA-256 for integrity check
- Optional signature verification (minisign/openssl) when tools available

## Auth Token

- Generated during install at `var/.auth_token` (permissions: 0600)
- Required for WebUI API access
- View: `cat /opt/keenetic-debug/var/.auth_token`
- Rotate: `keenetic-debug webui token rotate`
- Roles: `admin` (full access), `readonly` (view only)

## Verify Installation

```shell
sh install.sh --verify
```

## Release Artifacts

Each release contains:
- `keenetic-debug-X.Y.Z-offline-<arch>.tar.gz` — full offline bundle per architecture
- `release-manifest.json` — version, URLs, sha256 checksums
- `checksums.sha256` — SHA-256 for all artifacts
