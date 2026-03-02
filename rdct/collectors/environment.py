from __future__ import annotations

import shutil
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import write_json


def _which(cmd: str) -> Optional[str]:
    return shutil.which(cmd)


class EnvironmentDetectorCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-02-environment",
        name="EnvironmentDetectorCollector",
        version="1.0.0",
        category="environment",
        requires_root=False,
        default_enabled=True,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = time.time()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        # KeeneticOS version/build (best-effort)
        keen_ver = None
        keen_build = None
        for p in ["/etc/version", "/etc/ndm/version", "/etc/keenetic/version"]:
            try:
                txt = Path(p).read_text(encoding="utf-8", errors="ignore").strip()
                if txt:
                    keen_ver = txt
                    break
            except Exception:
                pass

        # Try ndmc
        try:
            cr = self._run_cmd(ctx, ["ndmc", "-c", "show version"], timeout_sec=10, sensitive_output=False)
            if cr.exit_code == 0 and cr.stdout_path:
                txt = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore")
                # Keep raw; parse lightly
                keen_build = txt.strip()[:2000]
        except Exception:
            pass

        keeneticos = {
            "version": keen_ver or "unknown",
            "build": keen_build,
            "components": [],
        }

        # Entware detection
        opt_path = Path("/opt")
        entware_present = opt_path.exists() and opt_path.is_dir()
        opkg_path = _which("opkg")
        opkg_present = bool(opkg_path)
        opkg_version = None
        packages_count = None

        if opkg_present:
            try:
                cr = self._run_cmd(ctx, ["opkg", "--version"], timeout_sec=10)
                if cr.stdout_path:
                    opkg_version = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore").strip().splitlines()[0][:200]
            except Exception:
                pass
            try:
                cr = self._run_cmd(ctx, ["opkg", "list-installed"], timeout_sec=30)
                if cr.stdout_path:
                    packages_count = len([ln for ln in Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore").splitlines() if ln.strip()])
            except Exception:
                pass

        entware = {
            "present": bool(entware_present),
            "opt_path": str(opt_path) if entware_present else None,
            "opkg_present": bool(opkg_present),
            "opkg_version": opkg_version,
            "packages_count": packages_count,
        }

        # Tools inventory (minimal)
        tools = []
        for name in ["sh", "busybox", "ps", "top", "dmesg", "ip", "ss", "netstat", "curl", "wget", "tar", "gzip", "opkg", "ndmc"]:
            path = _which(name)
            tools.append({
                "name": name,
                "path": path,
                "version": None,
                "available": bool(path),
            })

        out_dir = ctx.snapshot_root / "environment"
        out_dir.mkdir(parents=True, exist_ok=True)
        p1 = out_dir / "keeneticos.json"
        p2 = out_dir / "entware.json"
        p3 = out_dir / "tools_inventory.json"
        write_json(p1, keeneticos)
        write_json(p2, entware)
        write_json(p3, tools)

        result["stats"]["items_collected"] = 3
        result["stats"]["files_written"] = 3
        result["stats"]["bytes_written"] = p1.stat().st_size + p2.stat().st_size + p3.stat().st_size
        for p, desc in [(p1, "KeeneticOS info"), (p2, "Entware info"), (p3, "Tools inventory")]:
            result["artifacts"].append({
                "path": str(p.relative_to(ctx.snapshot_root)),
                "type": "json",
                "size_bytes": p.stat().st_size,
                "sha256": None,
                "sensitive": False,
                "redacted": False,
                "description": desc,
            })

        result["normalized_data"] = {
            "entware_present": bool(entware_present),
            "tools_available": sorted([t["name"] for t in tools if t["available"]]),
        }

        # Signals
        ctx.signals["env.entware_present"] = bool(entware_present)
        ctx.signals["env.opkg_present"] = bool(opkg_present)
        if packages_count is not None:
            ctx.signals["entware.packages_count"] = packages_count

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
