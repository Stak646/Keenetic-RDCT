from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import redact_text, sha256_text, utc_now_iso, write_json


class EntwareOpkgCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-11-entware-opkg",
        name="EntwareOpkgCollector",
        version="1.0.0",
        category="entware",
        requires_root=False,
        default_enabled=True,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = time.time()
        result = self._result_template(ctx, status="partial")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        if not Path("/opt").exists():
            warnings.append({"time": utc_now_iso(), "level": "warning", "code": "opt_missing", "message": "/opt not found; Entware likely not installed."})
            self._finalize_result(ctx, result, started)
            self.write_result_json(ctx, result)
            self.write_errors_json(ctx, errors, warnings)
            return result

        # list-installed
        cr = self._run_cmd(ctx, ["opkg", "list-installed"], timeout_sec=40, sensitive_output=False)
        pkgs: List[Dict[str, str]] = []
        if cr.exit_code == 0 and cr.stdout_path:
            for ln in Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore").splitlines():
                ln = ln.strip()
                if not ln:
                    continue
                # format: name - version
                parts = [p.strip() for p in ln.split(" - ", 1)]
                if len(parts) == 2:
                    pkgs.append({"name": parts[0], "version": parts[1]})
                else:
                    pkgs.append({"name": ln, "version": ""})

        out_dir = ctx.snapshot_root / "entware" / "opkg"
        out_dir.mkdir(parents=True, exist_ok=True)
        p_inst = out_dir / "installed_packages.json"
        write_json(p_inst, {"count": len(pkgs), "packages": pkgs})

        # repos/config copies (redacted in light/medium)
        repos_text = ""
        conf_paths = [Path("/opt/etc/opkg.conf")]
        conf_dir = Path("/opt/etc/opkg")
        if conf_dir.exists():
            conf_paths.extend(sorted(conf_dir.glob("*.conf")))

        collected_confs = []
        for cp in conf_paths:
            try:
                if cp.exists():
                    txt = cp.read_text(encoding="utf-8", errors="ignore")
                    if ctx.redaction_enabled and ctx.research_mode in {"light","medium"}:
                        txt = redact_text(txt, ctx.redaction_level)
                    rel = f"entware/opkg/{cp.name}"
                    out_p = ctx.snapshot_root / rel
                    out_p.parent.mkdir(parents=True, exist_ok=True)
                    out_p.write_text(txt, encoding="utf-8", errors="ignore")
                    collected_confs.append(out_p)
            except Exception:
                continue

        status_summary = {
            "opkg_present": True,
            "packages_count": len(pkgs),
            "configs_copied": [str(p.relative_to(ctx.snapshot_root)) for p in collected_confs],
        }
        p_sum = out_dir / "status_summary.json"
        write_json(p_sum, status_summary)

        result["run"]["status"] = "success" if pkgs else "partial"
        result["stats"]["items_collected"] = len(pkgs)
        result["stats"]["files_written"] = 2 + len(collected_confs)
        result["stats"]["bytes_written"] = p_inst.stat().st_size + p_sum.stat().st_size + sum(p.stat().st_size for p in collected_confs)

        result["artifacts"].append(self._register_artifact(
            ctx,
            path=p_inst,
            type_="json",
            sensitive=False,
            redacted=False,
            description="Installed opkg packages",
            tags=["entware", "opkg"],
        ))
        for p in collected_confs:
            result["artifacts"].append(self._register_artifact(
                ctx,
                path=p,
                type_="text",
                sensitive=True,
                redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                description="opkg config/repository file (redacted in Light/Medium)",
                tags=["entware", "opkg"],
            ))
        result["artifacts"].append(self._register_artifact(
            ctx,
            path=p_sum,
            type_="json",
            sensitive=False,
            redacted=False,
            description="opkg status summary",
            tags=["entware", "opkg"],
        ))

        result["normalized_data"] = {"packages": sorted([f"{p['name']}={p.get('version','')}" for p in pkgs])}
        ctx.signals["entware.installed_packages"] = result["normalized_data"]["packages"]

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
