from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import utc_now_iso, write_json


class PerformanceProfileCollector(BaseCollector):
    META = CollectorMeta(
        name="PerformanceProfileCollector",
        version="1.0",
        collector_id="ext-14-performance-profile",
        category="system",
        requires_root=False,
        default_enabled=False,
        risk_level=1,
        cost_level=1,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = utc_now_iso()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        out_dir = ctx.snapshot_root / "system" / "performance"
        out_dir.mkdir(parents=True, exist_ok=True)

        artifacts = []

        # Commands
        for cmd, fname, desc in [
            (["uptime"], "uptime.txt", "uptime"),
            (["free"], "free.txt", "free"),
            (["sh", "-c", "top -b -n 1 2>/dev/null | head -n 80"], "top.txt", "top (head)"),
            (["df", "-h"], "df_h.txt", "df -h"),
        ]:
            try:
                cr = self._run_cmd(ctx, cmd, timeout_sec=int(ctx.limits.get("collector_timeout_sec", 30)), sensitive_output=False)
                text = ""
                if cr.stdout_path and Path(cr.stdout_path).exists():
                    text = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore")
                if not text.strip():
                    continue
                rel = str((out_dir / fname).relative_to(ctx.snapshot_root))
                p = self._write_text(ctx, rel, text, sensitive=False)
                artifacts.append(self._register_artifact(
                    ctx,
                    path=p,
                    type_="text",
                    sensitive=False,
                    redacted=False,
                    description=desc,
                    tags=["perf"],
                ))
            except Exception:
                continue

        summary = {
            "generated_at": utc_now_iso(),
            "artifacts_count": len(artifacts),
        }
        sum_path = out_dir / "performance_summary.json"
        write_json(sum_path, summary)
        artifacts.append(self._register_artifact(
            ctx,
            path=sum_path,
            type_="json",
            sensitive=False,
            redacted=False,
            description="Performance summary",
            tags=["perf"],
        ))

        if len(artifacts) <= 1:
            result["run"]["status"] = "partial"

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {"performance_profile_present": True}
        result["stats"]["items_collected"] = len(artifacts)
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = sum((ctx.snapshot_root / a["path"]).stat().st_size for a in artifacts if a.get("path"))

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
