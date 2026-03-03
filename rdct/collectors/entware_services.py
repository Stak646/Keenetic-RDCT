from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import utc_now_iso, write_json


class EntwareServicesCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-12-entware-services",
        name="EntwareServicesCollector",
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

        initd = Path("/opt/etc/init.d")
        if not initd.exists():
            warnings.append({"time": utc_now_iso(), "level": "warning", "code": "initd_missing", "message": "/opt/etc/init.d not found."})
            self._finalize_result(ctx, result, started)
            self.write_result_json(ctx, result)
            self.write_errors_json(ctx, errors, warnings)
            return result

        scripts = sorted([p for p in initd.iterdir() if p.is_file()])
        inventory = []
        statuses = []

        for p in scripts[:200]:
            inventory.append({
                "name": p.name,
                "path": str(p),
                "mode": oct(p.stat().st_mode & 0o777),
            })
            # best-effort status
            try:
                cr = self._run_cmd(ctx, [str(p), "status"], timeout_sec=5, sensitive_output=False)
                txt = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore") if cr.stdout_path else ""
                statuses.append({"name": p.name, "exit_code": cr.exit_code, "output": txt[:500]})
            except Exception:
                continue

        out_dir = ctx.snapshot_root / "entware" / "services"
        out_dir.mkdir(parents=True, exist_ok=True)
        p_inv = out_dir / "initd_inventory.json"
        p_status = out_dir / "status.json"
        write_json(p_inv, {"count": len(inventory), "scripts": inventory})
        write_json(p_status, {"count": len(statuses), "statuses": statuses})

        result["run"]["status"] = "success"
        result["stats"]["items_collected"] = len(inventory)
        result["stats"]["files_written"] = 2
        result["stats"]["bytes_written"] = p_inv.stat().st_size + p_status.stat().st_size

        for p, desc in [(p_inv, "init.d inventory"), (p_status, "init.d status outputs (truncated)")]:
            result["artifacts"].append(self._register_artifact(
                ctx,
                path=p,
                type_="json",
                sensitive=False,
                redacted=False,
                description=desc,
                tags=["entware", "services"],
            ))

        result["normalized_data"] = {"services": sorted([s["name"] for s in inventory])}
        ctx.signals["entware.services"] = result["normalized_data"]["services"]

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
