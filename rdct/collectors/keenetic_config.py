from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import redact_text, sha256_text, write_json


class KeeneticConfigCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-09-keenetic-config",
        name="KeeneticConfigCollector",
        version="1.0.0",
        category="keenetic",
        requires_root=False,
        default_enabled=True,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = time.time()
        result = self._result_template(ctx, status="partial")  # often limited
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        config_txt = ""
        method = None

        # Best-effort: use ndmc if present.
        try:
            cr = self._run_cmd(ctx, ["ndmc", "-c", "show running-config"], timeout_sec=15, sensitive_output=True)
            if cr.exit_code == 0 and cr.stdout_path:
                config_txt = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore")
                method = "ndmc show running-config"
        except Exception:
            pass

        if not config_txt:
            try:
                # fallback: show configuration
                cr = self._run_cmd(ctx, ["ndmc", "-c", "show configuration"], timeout_sec=15, sensitive_output=True)
                if cr.exit_code == 0 and cr.stdout_path:
                    config_txt = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore")
                    method = "ndmc show configuration"
            except Exception:
                pass

        redacted = False
        if config_txt:
            if ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}:
                config_txt = redact_text(config_txt, ctx.redaction_level)
                redacted = True

            out_cfg = ctx.snapshot_root / "keenetic" / "config_export.txt"
            out_cfg.parent.mkdir(parents=True, exist_ok=True)
            out_cfg.write_text(config_txt, encoding="utf-8", errors="ignore")

            meta = {
                "method": method,
                "redacted": redacted,
                "sha256_redacted": sha256_text(config_txt),
            }
            out_meta = ctx.snapshot_root / "keenetic" / "config_meta.json"
            write_json(out_meta, meta)

            result["run"]["status"] = "success"
            result["stats"]["items_collected"] = 1
            result["stats"]["files_written"] = 2
            result["stats"]["bytes_written"] = out_cfg.stat().st_size + out_meta.stat().st_size
            for p, typ, desc, sens in [
                (out_cfg, "text", "Keenetic config export", True),
                (out_meta, "json", "Config export metadata", False),
            ]:
                result["artifacts"].append({
                    "path": str(p.relative_to(ctx.snapshot_root)),
                    "type": typ,
                    "size_bytes": p.stat().st_size,
                    "sha256": None,
                    "sensitive": sens,
                    "redacted": redacted if sens else False,
                    "description": desc,
                })
            result["normalized_data"] = {"config_sha256": meta["sha256_redacted"]}
        else:
            warnings.append({
                "time": "",
                "level": "warning",
                "code": "keenetic_config_unavailable",
                "message": "Unable to export Keenetic config (ndmc unavailable or permission denied).",
                "context": {"hint": "Run as admin/root or enable ndmc CLI if needed."},
            })
            result["run"]["status"] = "partial"

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
