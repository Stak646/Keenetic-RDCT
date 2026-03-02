from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import write_json


_SEVERITY_ORDER = {"critical": 4, "high": 3, "medium": 2, "low": 1, "info": 0}


class SummaryCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-16-summary",
        name="SummaryCollector",
        version="1.0.0",
        category="reports",
        requires_root=False,
        default_enabled=True,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = time.time()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        # Gather findings from ctx.signals that core stored
        all_findings = ctx.signals.get("core.all_findings", [])
        all_findings_sorted = sorted(all_findings, key=lambda f: _SEVERITY_ORDER.get(f.get("severity","info"), 0), reverse=True)
        top = all_findings_sorted[:50]

        # Recommendations strictly from observed facts.
        recs: List[Dict[str, Any]] = []
        for f in top:
            code = f.get("code")
            if code == "fs_errors_in_dmesg":
                recs.append({"code": "check_usb_fs", "text": "USB filesystem errors detected: check the USB drive, try another drive/FS, run fsck on a PC."})
            if code == "oom_events_in_dmesg":
                recs.append({"code": "reduce_load", "text": "OOM events detected: reduce enabled services, lower concurrency/performance mode, check memory-heavy processes."})
            if code == "possible_admin_ui":
                recs.append({"code": "review_local_web_services", "text": "Possible local admin UI detected: verify it is expected and restrict access where possible."})

        out_dir = ctx.snapshot_root / "reports"
        out_dir.mkdir(parents=True, exist_ok=True)
        p_top = out_dir / "top_findings.json"
        p_rec = out_dir / "recommendations.json"
        write_json(p_top, {"count": len(top), "items": top})
        write_json(p_rec, {"count": len(recs), "items": recs})

        result["stats"]["items_collected"] = len(top)
        result["stats"]["files_written"] = 2
        result["stats"]["bytes_written"] = p_top.stat().st_size + p_rec.stat().st_size
        for p, desc in [(p_top, "Top findings"), (p_rec, "Recommendations (fact-based)")]:
            result["artifacts"].append({
                "path": str(p.relative_to(ctx.snapshot_root)),
                "type": "json",
                "size_bytes": p.stat().st_size,
                "sha256": None,
                "sensitive": True,
                "redacted": True,
                "description": desc,
            })

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
