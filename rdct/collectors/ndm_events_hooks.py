from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import write_json


class NDMEventsHooksCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-10-ndm-events-hooks",
        name="NDMEventsHooksCollector",
        version="1.0.0",
        category="keenetic",
        requires_root=False,
        default_enabled=True,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = time.time()
        result = self._result_template(ctx, status="partial")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        events_txt = ""
        hooks = []
        comps = []

        # Try ndmc logs
        try:
            cr = self._run_cmd(ctx, ["ndmc", "-c", "show system log"], timeout_sec=20, sensitive_output=True)
            if cr.exit_code == 0 and cr.stdout_path:
                events_txt = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore")
        except Exception:
            pass

        # Try known log files
        if not events_txt:
            for p in ["/var/log/ndm", "/var/log/messages", "/var/log/system.log", "/var/log/ndm.log"]:
                try:
                    if Path(p).exists():
                        events_txt = Path(p).read_text(encoding="utf-8", errors="ignore")
                        break
                except Exception:
                    pass

        # Components: attempt to parse ndmc show version output in environment collector.
        # Here, keep minimal placeholder.
        comps_path = ctx.snapshot_root / "keenetic" / "ndm" / "components.json"
        hooks_path = ctx.snapshot_root / "keenetic" / "ndm" / "hooks.json"
        events_path = ctx.snapshot_root / "keenetic" / "ndm" / "events.log"
        comps_path.parent.mkdir(parents=True, exist_ok=True)

        write_json(comps_path, {"components": comps})
        write_json(hooks_path, {"hooks": hooks})
        events_path.write_text(events_txt, encoding="utf-8", errors="ignore")

        written = [events_path, hooks_path, comps_path]
        result["run"]["status"] = "success" if events_txt else "partial"
        result["stats"]["items_collected"] = len(events_txt.splitlines()) if events_txt else 0
        result["stats"]["files_written"] = len(written)
        result["stats"]["bytes_written"] = sum(p.stat().st_size for p in written)

        for p, typ, desc in [
            (events_path, "text", "NDM events/logs snapshot"),
            (hooks_path, "json", "NDM hooks inventory (placeholder)"),
            (comps_path, "json", "NDM components inventory (placeholder)"),
        ]:
            result["artifacts"].append(self._register_artifact(
                ctx,
                path=p,
                type_=typ,
                sensitive=(typ == "text"),
                redacted=bool(ctx.redaction_enabled and typ == "text" and ctx.research_mode in {"light", "medium"}),
                description=desc,
                tags=["keenetic", "ndm"],
            ))

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
