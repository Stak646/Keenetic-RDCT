# RDCT — Router Diagnostic & Control Tool (USB-only)

This repository contains an **MVP implementation** of RDCT per the provided specification:
KeeneticOS + Entware diagnostic snapshot tool with **USB-only** storage, **CLI + WebUI/API**, **manifest**, **incremental baseline/delta**, and a **Policy Engine**.

For details see `docs/`.

## Quick start (CLI)

### One-command install from GitHub (recommended)

Run **one command** on the router (downloads RDCT onto the USB drive and creates `rdct.sh` wrapper in the base folder):

```sh
curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | \
  RDCT_GH_OWNER=<OWNER> RDCT_GH_REPO=<REPO> sh
```

Optional:

- choose USB base path explicitly:

```sh
curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | \
  RDCT_GH_OWNER=<OWNER> RDCT_GH_REPO=<REPO> RDCT_BASE=/tmp/mnt/sda1/rdct sh
```

After install:

```sh
/tmp/mnt/sda1/rdct/rdct.sh preflight
/tmp/mnt/sda1/rdct/rdct.sh run --mode light
/tmp/mnt/sda1/rdct/rdct.sh serve --bind 0.0.0.0 --port 8080
```

### Run directly (developer / local)

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
