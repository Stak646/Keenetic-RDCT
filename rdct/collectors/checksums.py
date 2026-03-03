from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Dict, List, Tuple

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import sha256_file


class ChecksumsCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-17-checksums",
        name="ChecksumsCollector",
        version="1.0.0",
        category="checksums",
        requires_root=False,
        default_enabled=True,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = time.time()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        out = ctx.snapshot_root / "checksums.sha256"
        lines: List[str] = []
        count = 0

        for p in sorted(ctx.snapshot_root.rglob("*")):
            if ctx.should_stop():
                break
            if p.is_dir():
                continue
            if p.name == "checksums.sha256":
                continue
            try:
                h = sha256_file(p)
                rel = str(p.relative_to(ctx.snapshot_root))
                lines.append(f"{h}  {rel}")
                count += 1
            except Exception:
                continue

        out.write_text("\n".join(lines) + "\n", encoding="utf-8")
        size = out.stat().st_size

        result["stats"]["items_collected"] = count
        result["stats"]["files_written"] = 1
        result["stats"]["bytes_written"] = size
        result["artifacts"].append(self._register_artifact(
            ctx,
            path=out,
            type_="sha256",
            sensitive=False,
            redacted=False,
            description="Snapshot checksums (sha256)",
            tags=["checksums"],
        ))
        result["normalized_data"] = {"covered_files_count": count}

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
