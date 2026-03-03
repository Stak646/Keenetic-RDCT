from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, Optional

from .config import ConfigManager
from .core import RDCTCore
from .archive import create_redacted_export
from .storage import build_layout, detect_usb_mounts
from .web.server import serve
from .debugger import write_crash_report
from .apps import AppManager, AppManagerError


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

    exp = sub.add_parser("export", help="Create a redacted export bundle for sharing")
    exp.add_argument("--run-id", required=True, help="Run ID to export")
    exp.add_argument("--level", choices=["strict", "normal", "off"], default=None, help="Redaction level")
    exp.add_argument("--out-dir", default=None, help="Override export output directory")

    apps = sub.add_parser("apps", help="Allowlist App Manager")
    apps_sub = apps.add_subparsers(dest="apps_cmd", required=True)
    apps_sub.add_parser("list", help="List allowlisted apps")
    apps_sub.add_parser("status", help="Show installed status")

    a_install = apps_sub.add_parser("install", help="Install an allowlisted app (network required)")
    a_install.add_argument("app_id")

    a_update = apps_sub.add_parser("update", help="Update an allowlisted app (network required)")
    a_update.add_argument("app_id")

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
            try:
                cr = write_crash_report(layout.logs_dir / "crash", e, context={"cmd": "run", "base": str(base)})
                print(f"Crash report: {cr}", file=sys.stderr)
            except Exception:
                pass
            print(f"FAIL: {e}", file=sys.stderr)
            return 4

    if args.cmd == "serve":
        bind = args.bind if args.bind is not None else str(cfg.get("server", {}).get("bind", "0.0.0.0"))
        port = args.port if args.port is not None else int(cfg.get("server", {}).get("port", 0) or 0)
        try:
            return serve(base, bind, port)
        except Exception as e:
            try:
                cr = write_crash_report(layout.logs_dir / "crash", e, context={"cmd": "serve", "base": str(base)})
                print(f"Crash report: {cr}", file=sys.stderr)
            except Exception:
                pass
            raise

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

    if args.cmd == "export":
        run_id = str(args.run_id)
        snap = layout.reports_dir / run_id / "snapshot"
        if not snap.exists():
            print(f"ERROR: snapshot not found for run_id={run_id}: {snap}", file=sys.stderr)
            return 5
        out_dir = Path(args.out_dir) if args.out_dir else (layout.reports_dir / run_id / "exports")
        level = str(args.level or (cfg.get("exports", {}) or {}).get("default_redaction_level") or "strict")
        try:
            out = create_redacted_export(snapshot_root=snap, out_dir=out_dir, level=level)
            print(str(out))
            return 0
        except Exception as e:
            try:
                cr = write_crash_report(layout.logs_dir / "crash", e, context={"cmd": "export", "base": str(base), "run_id": run_id})
                print(f"Crash report: {cr}", file=sys.stderr)
            except Exception:
                pass
            print(f"FAIL: {e}", file=sys.stderr)
            return 6

    if args.cmd == "apps":
        mgr = AppManager(base)
        if args.apps_cmd == "list":
            for a in mgr.load_catalog():
                print(f"- {a.get('app_id')}: {a.get('name')}")
            return 0
        if args.apps_cmd == "status":
            sts = mgr.list_status()
            for s in sts:
                flag = "installed" if s.installed else "not installed"
                extra = f" (opkg: {s.opkg_version})" if s.opkg_installed and s.opkg_version else ""
                print(f"- {s.app_id}: {flag}{extra}")
            return 0
        if args.apps_cmd == "install":
            try:
                res = mgr.install(str(args.app_id))
                print(json.dumps(res, ensure_ascii=False, indent=2))
                return 0
            except AppManagerError as e:
                print(f"FAIL: {e}", file=sys.stderr)
                return 7
        if args.apps_cmd == "update":
            try:
                res = mgr.update(str(args.app_id))
                print(json.dumps(res, ensure_ascii=False, indent=2))
                return 0
            except AppManagerError as e:
                print(f"FAIL: {e}", file=sys.stderr)
                return 8
        print("Unknown apps subcommand", file=sys.stderr)
        return 1

    print("Unknown command", file=sys.stderr)
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
