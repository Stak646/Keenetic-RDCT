from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import write_json


class NetworkBasicsCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-06-network-basics",
        name="NetworkBasicsCollector",
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

        cr1 = self._run_cmd(ctx, ["ip", "addr"], timeout_sec=10, sensitive_output=False)
        cr2 = self._run_cmd(ctx, ["ip", "link"], timeout_sec=10, sensitive_output=False)
        cr3 = self._run_cmd(ctx, ["ip", "neigh"], timeout_sec=10, sensitive_output=True)

        ip_addr = Path(cr1.stdout_path).read_text(encoding="utf-8", errors="ignore") if cr1.stdout_path else ""
        ip_link = Path(cr2.stdout_path).read_text(encoding="utf-8", errors="ignore") if cr2.stdout_path else ""
        neigh = Path(cr3.stdout_path).read_text(encoding="utf-8", errors="ignore") if cr3.stdout_path else ""

        p1 = self._write_text(ctx, "network/ip_addr.txt", ip_addr, sensitive=False)
        p2 = self._write_text(ctx, "network/ip_link.txt", ip_link, sensitive=False)
        p3 = self._write_text(ctx, "network/neigh.txt", neigh, sensitive=True)

        # normalized: interface list
        interfaces = []
        for ln in ip_link.splitlines():
            if ": " in ln and ln[0].isdigit():
                # "2: eth0: <...>"
                name = ln.split(": ", 2)[1].split(":", 1)[0]
                interfaces.append(name)

        norm = {
            "interfaces": sorted(set(interfaces)),
            "neigh_count": len([ln for ln in neigh.splitlines() if ln.strip()]),
        }
        p_norm = ctx.snapshot_root / "network" / "interfaces_summary.json"
        write_json(p_norm, norm)

        result["stats"]["items_collected"] = len(norm["interfaces"])
        result["stats"]["files_written"] = 4
        result["stats"]["bytes_written"] = p1.stat().st_size + p2.stat().st_size + p3.stat().st_size + p_norm.stat().st_size

        for pp, typ, desc, sens in [
            (p1, "text", "ip addr", False),
            (p2, "text", "ip link", False),
            (p3, "text", "ip neigh", True),
            (p_norm, "json", "interfaces summary", False),
        ]:
            result["artifacts"].append({
                "path": str(pp.relative_to(ctx.snapshot_root)),
                "type": typ,
                "size_bytes": pp.stat().st_size,
                "sha256": None,
                "sensitive": sens,
                "redacted": bool(ctx.redaction_enabled and sens and ctx.research_mode in {"light","medium"}),
                "description": desc,
            })

        result["normalized_data"] = norm
        ctx.signals["network.interfaces_count"] = len(norm["interfaces"])

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
