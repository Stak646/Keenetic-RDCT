from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import sha256_text, utc_now_iso, write_json


class RecentChangesCollector(BaseCollector):
    META = CollectorMeta(
        name="RecentChangesCollector",
        version="1.0",
        collector_id="ext-08-recent-changes",
        category="system",
        requires_root=False,
        default_enabled=False,
        risk_level=2,
        cost_level=3,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = utc_now_iso()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        days = int((ctx.limits.get("recent_changes_days") or 7))
        targets = ["/opt", "/etc"]

        out_dir = ctx.snapshot_root / "system" / "recent_changes"
        out_dir.mkdir(parents=True, exist_ok=True)

        cmd_tpl = "find {t} -xdev -type f -mtime -{days} -ls 2>/dev/null | head -n 5000"
        texts: List[str] = []
        for t in targets:
            try:
                cr = self._run_cmd(ctx, ["sh", "-c", cmd_tpl.format(t=t, days=days)], timeout_sec=int(ctx.limits.get("collector_timeout_sec", 60)), sensitive_output=True)
                if cr.stdout_path and Path(cr.stdout_path).exists():
                    txt = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore")
                    if txt.strip():
                        texts.append(f"# {t}\n" + txt)
            except Exception:
                continue

        combined = "\n".join(texts)
        artifacts = []
        if combined.strip():
            rel = str((out_dir / "recent_files.txt").relative_to(ctx.snapshot_root))
            p = self._write_text(ctx, rel, combined, sensitive=True)
            artifacts.append(self._register_artifact(
                ctx,
                path=p,
                type_="text",
                sensitive=True,
                redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                description=f"Recently modified files (last {days} days; limited)",
                tags=["recent", "filesystem"],
            ))

        summary = {
            "days": days,
            "targets": targets,
            "combined_sha256": sha256_text(combined) if combined.strip() else None,
            "present": bool(combined.strip()),
        }
        sum_path = out_dir / "recent_changes_summary.json"
        write_json(sum_path, summary)
        artifacts.append(self._register_artifact(
            ctx,
            path=sum_path,
            type_="json",
            sensitive=False,
            redacted=False,
            description="Recent changes summary",
            tags=["recent", "filesystem"],
        ))

        if not combined.strip():
            result["run"]["status"] = "partial"

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {"recent_changes_sha256": summary.get("combined_sha256")}
        result["stats"]["items_collected"] = len(combined.splitlines()) if combined.strip() else 0
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = sum((ctx.snapshot_root / a["path"]).stat().st_size for a in artifacts if a.get("path"))

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
