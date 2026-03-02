from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..storage import read_proc_mounts, statvfs_bytes
from ..utils import write_json


class StorageMountDfCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-03-storage",
        name="StorageMountDfCollector",
        version="1.0.0",
        category="system",
        requires_root=False,
        default_enabled=True,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = time.time()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        mounts = read_proc_mounts()
        mounts_txt = "\n".join([f"{m.device} {m.mountpoint} {m.fstype} {','.join(m.options)}" for m in mounts]) + "\n"

        # df (best-effort)
        cr = self._run_cmd(ctx, ["df", "-h"], timeout_sec=10, sensitive_output=False)
        df_txt = ""
        if cr.stdout_path:
            df_txt = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore")

        free, total = statvfs_bytes(ctx.snapshot_root)
        summary = {
            "snapshot_root": str(ctx.snapshot_root),
            "free_space_bytes_at_collect": free,
            "total_space_bytes_at_collect": total,
        }

        p_mount = self._write_text(ctx, "system/mount.txt", mounts_txt, sensitive=False)
        p_df = self._write_text(ctx, "system/df.txt", df_txt, sensitive=False)
        p_sum = ctx.snapshot_root / "system" / "storage_summary.json"
        write_json(p_sum, summary)

        result["stats"]["items_collected"] = 3
        result["stats"]["files_written"] = 3
        result["stats"]["bytes_written"] = p_mount.stat().st_size + p_df.stat().st_size + p_sum.stat().st_size

        for p, typ, desc in [(p_mount, "text", "mount output"), (p_df, "text", "df output"), (p_sum, "json", "storage summary")]:
            result["artifacts"].append({
                "path": str(p.relative_to(ctx.snapshot_root)),
                "type": typ,
                "size_bytes": p.stat().st_size,
                "sha256": None,
                "sensitive": False,
                "redacted": False,
                "description": desc,
            })

        ctx.signals["system.usb_free_bytes"] = free

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
