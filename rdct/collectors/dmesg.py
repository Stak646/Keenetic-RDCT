from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import write_json


_FS_ERR_RE = re.compile(r"(?i)(I/O error|EXT\d-fs error|FAT-fs|ntfs.*error|corruption|read-only file system)")
_OOM_RE = re.compile(r"(?i)(Out of memory|oom-killer|Killed process)")


class DmesgCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-05-dmesg",
        name="DmesgCollector",
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

        cr = self._run_cmd(ctx, ["dmesg"], timeout_sec=15, sensitive_output=False)
        txt = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore") if cr.stdout_path else ""
        p = self._write_text(ctx, "system/dmesg.txt", txt, sensitive=False)

        # Extract error-ish lines
        err_lines = []
        fs_err = False
        oom = False
        for ln in txt.splitlines():
            if _FS_ERR_RE.search(ln):
                fs_err = True
                err_lines.append(ln)
            if _OOM_RE.search(ln):
                oom = True
                err_lines.append(ln)
            if "error" in ln.lower() or "fail" in ln.lower():
                if len(err_lines) < 200:
                    err_lines.append(ln)

        p_err = ctx.snapshot_root / "system" / "dmesg_errors.json"
        write_json(p_err, {"count": len(err_lines), "lines": err_lines[:500]})

        result["stats"]["items_collected"] = len(err_lines)
        result["stats"]["files_written"] = 2
        result["stats"]["bytes_written"] = p.stat().st_size + p_err.stat().st_size
        for pp, typ, desc in [(p, "text", "dmesg snapshot"), (p_err, "json", "dmesg errors extract")]:
            result["artifacts"].append(self._register_artifact(
                ctx,
                path=pp,
                type_=typ,
                sensitive=False,
                redacted=False,
                description=desc,
                tags=["system", "dmesg"],
            ))

        if fs_err:
            result["findings"].append({
                "severity": "high",
                "code": "fs_errors_in_dmesg",
                "title": "Filesystem errors detected in dmesg",
                "details": "dmesg contains filesystem I/O/corruption messages. USB health may be degraded.",
                "refs": [str(p_err.relative_to(ctx.snapshot_root))],
            })
            ctx.signals["system.fs_errors_in_dmesg"] = True
        if oom:
            result["findings"].append({
                "severity": "high",
                "code": "oom_events_in_dmesg",
                "title": "OOM events detected in dmesg",
                "details": "dmesg contains Out-Of-Memory killer indications.",
                "refs": [str(p_err.relative_to(ctx.snapshot_root))],
            })
            ctx.signals["system.oom_in_dmesg"] = True

        result["normalized_data"] = {
            "fs_errors": fs_err,
            "oom_events": oom,
        }

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
