# Architecture (MVP)

RDCT is structured as:

- **CLI** (`rdct/cli.py`): init, preflight, run, serve
- **Core Orchestrator** (`rdct/core.py`): run lifecycle, phases, manifests, archives
- **Collectors** (`rdct/collectors/*`): pluggable modules for data gathering
- **Incremental Engine** (`rdct/incremental/*`): baseline/delta storage and diff report
- **Policy Engine** (`rdct/policy/*`): adaptive triggers → plan
- **WebUI/API** (`rdct/web/server.py` + `rdct/web/static/*`): local UI and API with token auth

## USB-only enforcement

Preflight reads `/proc/mounts` and refuses to run unless the base path is on an external mount (heuristics for `/dev/sd*`, `/dev/mmcblk*`, etc.).
All outputs go to:

- deps/
- cache/
- run/
- reports/
- logs/

No internal memory writes are intended (TMPDIR is redirected into snapshot logs tmp where possible).

## Phases

1. Phase 1: essential collectors (device/env/storage/proc/dmesg/network/opkg/etc)
2. Policy evaluation → `snapshot/adaptive/plan.json`
3. Phase 2: optional collectors (web discovery, sensitive scan, mirror)
4. Phase 3: diff report (baseline vs target)
5. Phase 4: summary + checksums
6. Manifest + archive

## Extensibility

- Add a collector: implement `BaseCollector.run()` and register it in `collectors/__init__.py`
- Add a policy rule: edit `policy/rules.json` and/or expand evaluation mapping in `policy/engine.py`
