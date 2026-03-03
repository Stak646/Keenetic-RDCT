# Quickstart

## 1) Install

See `docs/INSTALL.md`.

## 2) Preflight

```sh
/tmp/mnt/sda1/rdct/rdct.sh preflight
```

If preflight fails, RDCT will refuse to run (USB-only is enforced).

## 3) Run a snapshot

```sh
/tmp/mnt/sda1/rdct/rdct.sh run --mode light
```

Modes:

- `light` — fastest, minimal, web probes disabled
- `medium` — more network/app diagnostics
- `full` — includes heavy collectors (filesystem checks, mirror)
- `extreme` — maximum depth (still respects safety gates)

## 4) Open WebUI

```sh
/tmp/mnt/sda1/rdct/rdct.sh serve --bind 0.0.0.0 --port 8080
```

Then open:

- `http://<router-ip>:8080/`

Token is stored in:

- `<base>/config/rdct.json` → `server.token`

## 5) Export a redacted bundle

Use a strict redaction level before sharing:

```sh
/tmp/mnt/sda1/rdct/rdct.sh export --run-id <RUN_ID> --level strict
```

The export is placed under:

- `<base>/reports/<RUN_ID>/exports/`
