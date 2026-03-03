from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import utc_now_iso, write_json


class AllowlistAppsCollector(BaseCollector):
    META = CollectorMeta(
        name="AllowlistAppsCollector",
        version="1.0",
        collector_id="ext-12-allowlist-apps",
        category="apps",
        requires_root=False,
        default_enabled=False,
        risk_level=1,
        cost_level=1,
    )

    def _read_json(self, p: Path) -> Optional[Dict[str, Any]]:
        try:
            if not p.exists():
                return None
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            return None

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = utc_now_iso()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        allow = ctx.signals.get("config.allowlist.apps") or []
        if not isinstance(allow, list):
            allow = []
        allow_set = {str(x) for x in allow}

        inv = self._read_json(ctx.snapshot_root / "apps" / "apps_inventory.json") or {}
        detected = inv.get("detected_apps") if isinstance(inv, dict) else []
        detected_ids: List[str] = []
        if isinstance(detected, list):
            for d in detected:
                if isinstance(d, dict) and d.get("app_id"):
                    detected_ids.append(str(d["app_id"]))

        not_allowed = sorted([a for a in set(detected_ids) if a not in allow_set])

        report = {
            "generated_at": utc_now_iso(),
            "allowlist": sorted(allow_set),
            "detected_apps": sorted(set(detected_ids)),
            "not_allowlisted": not_allowed,
        }
        out_path = ctx.snapshot_root / "apps" / "allowlist_report.json"
        write_json(out_path, report)

        artifacts = [
            self._register_artifact(
                ctx,
                path=out_path,
                type_="json",
                sensitive=False,
                redacted=False,
                description="Allowlist comparison report",
                tags=["apps", "allowlist"],
            )
        ]

        if not_allowed:
            result.setdefault("findings", []).append(
                {
                    "severity": "high",
                    "code": "apps_not_allowlisted",
                    "title": "Detected apps not in allowlist",
                    "details": f"Detected applications not present in allowlist: {not_allowed}.",
                    "refs": [{"path": str(out_path.relative_to(ctx.snapshot_root)), "type": "artifact"}],
                }
            )

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {"apps_not_allowlisted": not_allowed}
        result["stats"]["items_collected"] = len(detected_ids)
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = out_path.stat().st_size

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
