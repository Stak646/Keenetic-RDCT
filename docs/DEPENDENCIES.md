# Dependencies & Auto-install

RDCT can optionally install missing utilities required by collectors.

## Registry

RDCT uses a local registry file on USB:

- `<base>/deps/registry.json`

It records:

- what was installed
- when it was installed
- by which component

## Offline mode

If the router has no network access, RDCT switches to **offline** mode:

- skips auto-install
- disables collectors that require missing tools

## Configuration

See `docs/CONFIG_REFERENCE.md` → `dependencies` and `modes.network_policy`.
