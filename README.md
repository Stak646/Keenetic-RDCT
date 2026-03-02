# RDCT — Router Diagnostic & Control Tool (USB-only)

This repository contains an **MVP implementation** of RDCT per the provided specification:
KeeneticOS + Entware diagnostic snapshot tool with **USB-only** storage, **CLI + WebUI/API**, **manifest**, **incremental baseline/delta**, and a **Policy Engine**.

For details see `docs/`.

## Quick start (CLI)

```sh
python3 -m rdct --base /tmp/mnt/sda1/rdct init
python3 -m rdct --base /tmp/mnt/sda1/rdct preflight
python3 -m rdct --base /tmp/mnt/sda1/rdct run --mode light
python3 -m rdct --base /tmp/mnt/sda1/rdct reports
```

## WebUI/API

```sh
python3 -m rdct --base /tmp/mnt/sda1/rdct serve --bind 0.0.0.0 --port 8080
```

Open `http://<router-ip>:8080/` and paste `server.token` from `config/rdct.json`.

## Storage layout (USB)

- `cache/` – incremental index and normalized run data
- `run/` – staging area for the current run
- `reports/<run_id>/snapshot/` – finalized snapshot
- `reports/<run_id>/<run_id>.tar.gz` – archive
- `logs/tool/rdct.log` – tool log
