from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, Optional

from .config import ConfigManager
from .core import RDCTCore
from .storage import build_layout, detect_usb_mounts
from .web.server import serve


def autodetect_base_path() -> Optional[Path]:
    usb = detect_usb_mounts()
    if not usb:
        return None
    # Choose the first external mount and create /rdct within it
    mp = Path(usb[0].mountpoint)
    return (mp / "rdct")


def _parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(prog="rdct", description="RDCT — Router Diagnostic & Control Tool (USB-only)")
    p.add_argument("--base", help="Base path on USB (e.g. /tmp/mnt/sda1/rdct). If omitted, auto-detect first USB mount.", default=None)

    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("init", help="Create config on USB if missing")

    sub.add_parser("preflight", help="Run USB-only preflight checks")

    runp = sub.add_parser("run", help="Run diagnostics and create a snapshot")
    runp.add_argument("--mode", choices=["light","medium","full","extreme"], help="Research mode override")
    runp.add_argument("--perf", choices=["lite","middle","hard","auto"], help="Performance mode override")
    runp.add_argument("--baseline", action="store_true", help="Force baseline run (reset baseline)")
    runp.add_argument("--initiator", default="cli", help="Initiator label (cli/webui/api)")

    serv = sub.add_parser("serve", help="Start WebUI/API server")
    serv.add_argument("--bind", default=None, help="Bind address (default from config.server.bind)")
    serv.add_argument("--port", type=int, default=None, help="Port (default from config.server.port; 0=auto)")

    rep = sub.add_parser("reports", help="List existing reports")
    rep.add_argument("--json", action="store_true")

    return p.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    args = _parse_args(argv)

    base = Path(args.base) if args.base else autodetect_base_path()
    if not base:
        print("ERROR: USB mount not detected. Provide --base on an external USB mount.", file=sys.stderr)
        return 2

    layout = build_layout(base)
    cfg_mgr = ConfigManager(base)
    cfg = cfg_mgr.load_or_create()

    core = RDCTCore(layout, cfg)

    if args.cmd == "init":
        print(f"Config path: {cfg_mgr.config_path}")
        print("OK")
        return 0

    if args.cmd == "preflight":
        try:
            core.preflight()
            print("OK: USB-only preflight passed")
            return 0
        except Exception as e:
            print(f"FAIL: {e}", file=sys.stderr)
            return 3

    if args.cmd == "run":
        try:
            rr = core.run(initiator=str(args.initiator), requested_mode=args.mode, requested_perf=args.perf, force_baseline=bool(args.baseline))
            print(f"run_id: {rr.run_id}")
            print(f"status: {rr.status}")
            print(f"snapshot: {rr.snapshot_path}")
            if rr.archive_path:
                print(f"archive: {rr.archive_path}")
            print(f"manifest: {rr.manifest_path}")
            return 0
        except Exception as e:
            print(f"FAIL: {e}", file=sys.stderr)
            return 4

    if args.cmd == "serve":
        bind = args.bind if args.bind is not None else str(cfg.get("server", {}).get("bind", "0.0.0.0"))
        port = args.port if args.port is not None else int(cfg.get("server", {}).get("port", 0) or 0)
        return serve(base, bind, port)

    if args.cmd == "reports":
        reports_dir = layout.reports_dir
        items = []
        if reports_dir.exists():
            for d in sorted(reports_dir.iterdir(), reverse=True):
                if d.is_dir():
                    run_id = d.name
                    items.append({
                        "run_id": run_id,
                        "archive": str(d / f"{run_id}.tar.gz"),
                        "manifest": str(d / "snapshot" / "manifest.json"),
                    })
        if args.json:
            print(json.dumps({"count": len(items), "items": items}, ensure_ascii=False, indent=2))
        else:
            for it in items:
                print(f"- {it['run_id']}: {it['archive']}")
        return 0

    print("Unknown command", file=sys.stderr)
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
