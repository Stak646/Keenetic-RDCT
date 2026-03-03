from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import redact_text, sha256_text, write_json


class ProcSnapshotCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-04-proc-snapshot",
        name="ProcSnapshotCollector",
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

        cr_ps = self._run_cmd(ctx, ["ps", "w"], timeout_sec=10, sensitive_output=True)
        ps_txt = Path(cr_ps.stdout_path).read_text(encoding="utf-8", errors="ignore") if cr_ps.stdout_path else ""
        # In Light/Medium redact aggressively
        if ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}:
            ps_txt = redact_text(ps_txt, ctx.redaction_level)

        cr_top = self._run_cmd(ctx, ["top", "-b", "-n", "1"], timeout_sec=10, sensitive_output=True)
        top_txt = Path(cr_top.stdout_path).read_text(encoding="utf-8", errors="ignore") if cr_top.stdout_path else ""
        if ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}:
            top_txt = redact_text(top_txt, ctx.redaction_level)

        p_ps = self._write_text(ctx, "system/ps.txt", ps_txt, sensitive=True)
        p_top = self._write_text(ctx, "system/top.txt", top_txt, sensitive=True)

        # normalized process signatures: exe_hash+cmdline_hash+user
        signatures: List[Dict[str, Any]] = []
        lines = ps_txt.splitlines()
        if lines:
            header = lines[0]
        for ln in lines[1:]:
            # try to parse formats: PID USER VSZ STAT COMMAND
            parts = ln.split(None, 4)
            if len(parts) < 5:
                continue
            pid_s, user, vsz, stat, cmd = parts
            cmd_red = cmd
            if ctx.redaction_enabled and ctx.research_mode in {"light","medium"}:
                cmd_red = redact_text(cmd_red, ctx.redaction_level)
            sig = sha256_text(f"{user}|{cmd_red}")
            signatures.append({
                "pid": int(pid_s) if pid_s.isdigit() else None,
                "user": user,
                "cmdline_redacted": cmd_red,
                "signature": sig,
            })

        tree_path = ctx.snapshot_root / "system" / "process_tree.json"
        write_json(tree_path, {"processes": signatures})

        result["stats"]["items_collected"] = len(signatures)
        result["stats"]["files_written"] = 3
        result["stats"]["bytes_written"] = p_ps.stat().st_size + p_top.stat().st_size + tree_path.stat().st_size

        for p, typ, desc in [(p_ps, "text", "ps snapshot"), (p_top, "text", "top snapshot"), (tree_path, "json", "process signatures")]:
            result["artifacts"].append(self._register_artifact(
                ctx,
                path=p,
                type_=typ,
                sensitive=(typ == "text"),
                redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                description=desc,
                tags=["system", "processes"],
            ))

        result["normalized_data"] = {"process_signatures": [p["signature"] for p in signatures]}

        ctx.signals["system.process_count"] = len(signatures)

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
