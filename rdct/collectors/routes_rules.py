from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import sha256_text, write_json


class RoutesRulesCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-07-routes-rules",
        name="RoutesRulesCollector",
        version="1.0.0",
        category="network",
        requires_root=False,
        default_enabled=True,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = time.time()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        cr1 = self._run_cmd(ctx, ["ip", "route"], timeout_sec=10, sensitive_output=False)
        cr2 = self._run_cmd(ctx, ["ip", "rule"], timeout_sec=10, sensitive_output=False)

        routes = Path(cr1.stdout_path).read_text(encoding="utf-8", errors="ignore") if cr1.stdout_path else ""
        rules = Path(cr2.stdout_path).read_text(encoding="utf-8", errors="ignore") if cr2.stdout_path else ""

        p1 = self._write_text(ctx, "network/routes.txt", routes, sensitive=False)
        p2 = self._write_text(ctx, "network/rules.txt", rules, sensitive=False)

        result["stats"]["items_collected"] = len([ln for ln in routes.splitlines() if ln.strip()])
        result["stats"]["files_written"] = 2
        result["stats"]["bytes_written"] = p1.stat().st_size + p2.stat().st_size

        for pp, typ, desc in [(p1, "text", "ip route"), (p2, "text", "ip rule")]:
            result["artifacts"].append({
                "path": str(pp.relative_to(ctx.snapshot_root)),
                "type": typ,
                "size_bytes": pp.stat().st_size,
                "sha256": None,
                "sensitive": False,
                "redacted": False,
                "description": desc,
            })

        result["normalized_data"] = {
            "routes_sha256": sha256_text(routes),
            "rules_sha256": sha256_text(rules),
        }

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
