from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import sha256_text, utc_now_iso, write_json


class FirewallCollector(BaseCollector):
    META = CollectorMeta(
        name="FirewallCollector",
        version="1.0",
        collector_id="ext-01-firewall",
        category="network",
        requires_root=True,
        default_enabled=False,
        risk_level=2,
        cost_level=2,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = utc_now_iso()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        out_dir = ctx.snapshot_root / "network" / "firewall"
        out_dir.mkdir(parents=True, exist_ok=True)

        texts: List[str] = []
        artifacts = []

        # iptables
        for cmd, fname, desc in [
            (["iptables-save"], "iptables_save.txt", "iptables-save"),
            (["iptables", "-S"], "iptables_rules.txt", "iptables -S"),
            (["ip6tables-save"], "ip6tables_save.txt", "ip6tables-save"),
            (["ip6tables", "-S"], "ip6tables_rules.txt", "ip6tables -S"),
            (["nft", "list", "ruleset"], "nft_ruleset.txt", "nft list ruleset"),
        ]:
            try:
                cr = self._run_cmd(ctx, cmd, timeout_sec=int(ctx.limits.get("collector_timeout_sec", 30)), sensitive_output=True)
                text = ""
                if cr.stdout_path and Path(cr.stdout_path).exists():
                    text += Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore")
                if cr.stderr_path and Path(cr.stderr_path).exists():
                    errt = Path(cr.stderr_path).read_text(encoding="utf-8", errors="ignore")
                    if errt.strip():
                        text += "\n# STDERR\n" + errt

                if not text.strip():
                    continue
                rel = str((out_dir / fname).relative_to(ctx.snapshot_root))
                p = self._write_text(ctx, rel, text, sensitive=True)
                texts.append(text)
                artifacts.append(self._register_artifact(
                    ctx,
                    path=p,
                    type_="text",
                    sensitive=True,
                    redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                    description=desc,
                    tags=["firewall"],
                ))
            except Exception as e:
                warnings.append({"time": utc_now_iso(), "level": "warning", "code": "firewall_cmd_failed", "message": str(e), "context": {"cmd": cmd}})

        # Summary
        combined = "\n\n".join(texts)
        rules_count = 0
        if combined:
            for ln in combined.splitlines():
                s = ln.strip()
                if not s or s.startswith("#"):
                    continue
                rules_count += 1

        summary = {
            "collected": bool(texts),
            "rules_lines": rules_count,
            "combined_sha256": sha256_text(combined) if combined else None,
        }
        sum_path = out_dir / "firewall_summary.json"
        write_json(sum_path, summary)
        artifacts.append(self._register_artifact(
            ctx,
            path=sum_path,
            type_="json",
            sensitive=False,
            redacted=False,
            description="Firewall summary",
            tags=["firewall"],
        ))

        if not texts:
            result["run"]["status"] = "partial"
            result.setdefault("findings", []).append(
                {
                    "severity": "info",
                    "code": "firewall_not_collected",
                    "title": "Firewall rules not collected",
                    "details": "No firewall rule output was collected (missing commands or insufficient privileges).",
                    "refs": [{"path": str(sum_path.relative_to(ctx.snapshot_root)), "type": "artifact"}],
                }
            )

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {"firewall_rules_sha256": summary.get("combined_sha256")}
        result["stats"]["items_collected"] = int(rules_count)
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = sum((ctx.snapshot_root / a["path"]).stat().st_size for a in artifacts if a.get("path"))

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
