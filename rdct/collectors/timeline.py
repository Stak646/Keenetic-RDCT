from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import utc_now_iso, write_json


class TimelineCollector(BaseCollector):
    META = CollectorMeta(
        name="TimelineCollector",
        version="1.0",
        collector_id="ext-13-timeline",
        category="reports",
        requires_root=False,
        default_enabled=False,
        risk_level=2,
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

        out_dir = ctx.snapshot_root / "reports"
        out_dir.mkdir(parents=True, exist_ok=True)

        events: List[Dict[str, Any]] = []

        # dmesg errors
        dmesg_err = self._read_json(ctx.snapshot_root / "system" / "dmesg_errors.json") or {}
        for it in (dmesg_err.get("errors") or [])[:200]:
            if isinstance(it, dict):
                events.append(
                    {
                        "time": it.get("time"),
                        "source": "dmesg",
                        "level": it.get("level") or "warning",
                        "message": it.get("message"),
                    }
                )

        # ndm events (line-based)
        ndm_path = ctx.snapshot_root / "keenetic" / "ndm_events.log"
        if ndm_path.exists():
            try:
                lines = ndm_path.read_text(encoding="utf-8", errors="ignore").splitlines()[-500:]
                for ln in lines:
                    # If timestamp present, keep it, else None
                    m = re.match(r"^(\d{4}-\d{2}-\d{2}[ T].+?)\s+(.*)$", ln)
                    if m:
                        events.append({"time": m.group(1), "source": "ndm", "level": "info", "message": m.group(2)})
                    else:
                        events.append({"time": None, "source": "ndm", "level": "info", "message": ln})
            except Exception:
                pass

        # Coarse sort: prefer entries with time
        def key(e: Dict[str, Any]) -> str:
            return str(e.get("time") or "")

        events_sorted = sorted(events, key=key)
        timeline = {
            "generated_at": utc_now_iso(),
            "events_count": len(events_sorted),
            "events": events_sorted,
        }
        out_path = out_dir / "timeline.json"
        write_json(out_path, timeline)

        artifacts = [
            self._register_artifact(
                ctx,
                path=out_path,
                type_="json",
                sensitive=True,
                redacted=bool(ctx.redaction_enabled),
                description="Coarse event timeline",
                tags=["timeline"],
            )
        ]

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {"timeline_events_count": timeline.get("events_count")}
        result["stats"]["items_collected"] = int(timeline.get("events_count") or 0)
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = out_path.stat().st_size

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
