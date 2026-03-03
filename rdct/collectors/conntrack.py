from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import redact_text, sha256_text, utc_now_iso, write_json


class ConntrackCollector(BaseCollector):
    META = CollectorMeta(
        name="ConntrackCollector",
        version="1.0",
        collector_id="ext-02-conntrack",
        category="network",
        requires_root=True,
        default_enabled=False,
        risk_level=2,
        cost_level=2,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = utc_now_iso()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        out_dir = ctx.snapshot_root / "network" / "conntrack"
        out_dir.mkdir(parents=True, exist_ok=True)

        # Conntrack list can be huge. We cap via head.
        list_cmd = "conntrack -L 2>/dev/null | head -n 2000"
        stats_cmd = "conntrack -S 2>/dev/null"
        proc_fallback = Path("/proc/net/nf_conntrack")

        list_text = ""
        stats_text = ""

        try:
            cr = self._run_cmd(ctx, ["sh", "-c", list_cmd], timeout_sec=int(ctx.limits.get("collector_timeout_sec", 30)), sensitive_output=True)
            if cr.stdout_path and Path(cr.stdout_path).exists():
                list_text = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore")
        except Exception as e:
            warnings.append({"time": utc_now_iso(), "level": "warning", "code": "conntrack_list_failed", "message": str(e)})

        if not list_text and proc_fallback.exists():
            try:
                # Tail last ~2000 lines
                data = proc_fallback.read_text(encoding="utf-8", errors="ignore").splitlines()[-2000:]
                list_text = "\n".join(data) + "\n"
                warnings.append({"time": utc_now_iso(), "level": "warning", "code": "conntrack_used_proc_fallback", "message": "Used /proc/net/nf_conntrack fallback (tail)."})
            except Exception as e:
                warnings.append({"time": utc_now_iso(), "level": "warning", "code": "conntrack_proc_fallback_failed", "message": str(e)})

        try:
            cr = self._run_cmd(ctx, ["sh", "-c", stats_cmd], timeout_sec=int(ctx.limits.get("collector_timeout_sec", 30)), sensitive_output=True)
            if cr.stdout_path and Path(cr.stdout_path).exists():
                stats_text = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore")
        except Exception as e:
            warnings.append({"time": utc_now_iso(), "level": "warning", "code": "conntrack_stats_failed", "message": str(e)})

        artifacts = []
        if list_text:
            rel = str((out_dir / "conntrack_list.txt").relative_to(ctx.snapshot_root))
            p = self._write_text(ctx, rel, list_text, sensitive=True)
            artifacts.append(self._register_artifact(
                ctx,
                path=p,
                type_="text",
                sensitive=True,
                redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                description="Conntrack entries (limited head/tail)",
                tags=["conntrack"],
            ))
        if stats_text:
            rel = str((out_dir / "conntrack_stats.txt").relative_to(ctx.snapshot_root))
            p = self._write_text(ctx, rel, stats_text, sensitive=True)
            artifacts.append(self._register_artifact(
                ctx,
                path=p,
                type_="text",
                sensitive=True,
                redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                description="Conntrack stats",
                tags=["conntrack"],
            ))

        summary = {
            "entries_sample_lines": len(list_text.splitlines()) if list_text else 0,
            "stats_present": bool(stats_text.strip()),
            "list_sha256": sha256_text(list_text) if list_text else None,
            "stats_sha256": sha256_text(stats_text) if stats_text else None,
        }
        sum_path = out_dir / "conntrack_summary.json"
        write_json(sum_path, summary)
        artifacts.append(self._register_artifact(
            ctx,
            path=sum_path,
            type_="json",
            sensitive=False,
            redacted=False,
            description="Conntrack summary",
            tags=["conntrack"],
        ))

        if not list_text and not stats_text:
            result["run"]["status"] = "partial"
            result.setdefault("findings", []).append(
                {
                    "severity": "info",
                    "code": "conntrack_unavailable",
                    "title": "Conntrack data not collected",
                    "details": "conntrack command and /proc fallback were unavailable or empty.",
                    "refs": [{"path": str(sum_path.relative_to(ctx.snapshot_root)), "type": "artifact"}],
                }
            )

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {
            "conntrack_list_sha256": summary.get("list_sha256"),
        }
        result["stats"]["items_collected"] = int(summary["entries_sample_lines"])
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = sum((ctx.snapshot_root / a["path"]).stat().st_size for a in artifacts if a.get("path"))

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
