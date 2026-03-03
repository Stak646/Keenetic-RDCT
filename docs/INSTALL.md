# Installation

RDCT is designed for **KeeneticOS + Entware** and stores **all** data on an external USB drive (USB-only).

## One-command install from GitHub

Run on the router:

```sh
curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | \
  RDCT_GH_OWNER=<OWNER> RDCT_GH_REPO=<REPO> sh
```

Optional:

- Install into an explicit USB path:

```sh
curl -fsSL https://raw.githubusercontent.com/<OWNER>/<REPO>/main/install.sh | \
  RDCT_GH_OWNER=<OWNER> RDCT_GH_REPO=<REPO> RDCT_BASE=/tmp/mnt/sda1/rdct sh
```

What it does:

- Detects an external USB mount from `/proc/mounts`
- Creates the RDCT directory layout on USB
- Downloads the repository (or a release asset, if available) into `<base>/install`
- Creates `<base>/rdct.sh` wrapper (so you can run RDCT without `cd`)
- Initializes `config/rdct.json`

## Manual install (git clone)

If you prefer `git`:

```sh
git clone https://github.com/<OWNER>/<REPO>.git
cd <REPO>
# Run installer from the repo (it still installs to USB)
RDCT_GH_OWNER=<OWNER> RDCT_GH_REPO=<REPO> sh ./install.sh
```

## Requirements

- External USB drive mounted read-write
- `python3` (recommended via Entware)
- `curl` or `wget`, and `tar`

The installer can optionally install `python3` via `opkg` (Entware) if it is missing.

## Upgrade

Re-run the installer. It will re-download the tool into `<base>/install` and recreate `<base>/rdct.sh`.

## Uninstall

Delete the base folder from USB:

```sh
rm -rf /tmp/mnt/sda1/rdct
```

> RDCT never installs files into internal KeeneticOS storage.
