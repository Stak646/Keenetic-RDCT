# App Manager (Allowlist Apps)

RDCT includes an **allowlist-based App Manager** concept:

- It recognizes specific known apps (by processes/ports/config paths)
- It can create **app-specific debug bundles** in snapshots
- It can optionally help install/update allowlisted apps (GitHub releases)

## Safety

- Only allowlisted apps are supported
- Installs go to `<base>/apps/<app_id>/...` on USB
- No auto-start by default; start/stop requires explicit user action

## App catalog

See `rdct/apps/catalog.json`.

## CLI

```sh
/tmp/mnt/sda1/rdct/rdct.sh apps list
/tmp/mnt/sda1/rdct/rdct.sh apps status
/tmp/mnt/sda1/rdct/rdct.sh apps install <app_id>
/tmp/mnt/sda1/rdct/rdct.sh apps update <app_id>
```

> App installation/update requires network access.
