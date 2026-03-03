from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..incremental.diff import diff_normalized
from ..utils import utc_now_iso, write_json


class DiffCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-18-diff",
        name="DiffCollector",
        version="1.0.0",
        category="diff",
        requires_root=False,
        default_enabled=True,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = time.time()
        result = self._result_template(ctx, status="skipped")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        inc = ctx.signals.get("incremental", {})
        if not inc.get("enabled", False):
            self._finalize_result(ctx, result, started)
            self.write_result_json(ctx, result)
            self.write_errors_json(ctx, errors, warnings)
            return result

        baseline_run_id = inc.get("baseline_run_id")
        baseline_norm = inc.get("baseline_normalized")
        current_norm = inc.get("current_normalized")
        if not baseline_run_id or not baseline_norm or not current_norm:
            warnings.append({"time": utc_now_iso(), "level": "warning", "code": "diff_missing_baseline", "message": "No baseline data available; diff skipped."})
            self._finalize_result(ctx, result, started)
            self.write_result_json(ctx, result)
            self.write_errors_json(ctx, errors, warnings)
            return result

        scope = {
            "research_mode": ctx.research_mode,
            "redaction_level": ctx.redaction_level,
        }
        report = diff_normalized(baseline_norm, current_norm, baseline_run_id=baseline_run_id, target_run_id=ctx.run_id, scope=scope)

        out_dir = ctx.snapshot_root / "diff"
        out_dir.mkdir(parents=True, exist_ok=True)
        p = out_dir / "diff_report.json"
        write_json(p, report)

        result["run"]["status"] = "success"
        result["stats"]["items_collected"] = int(report["stats"]["total_changes"])
        result["stats"]["files_written"] = 1
        result["stats"]["bytes_written"] = p.stat().st_size
        result["artifacts"].append(self._register_artifact(
            ctx,
            path=p,
            type_="json",
            sensitive=True,
            redacted=bool(ctx.redaction_enabled),
            description="Diff report (baseline vs target)",
            tags=["diff", "incremental"],
        ))

        # Expose for manifest
        ctx.signals["incremental.diff_report_path"] = str(p.relative_to(ctx.snapshot_root))

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
