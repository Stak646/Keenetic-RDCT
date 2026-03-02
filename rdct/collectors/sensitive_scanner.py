from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Any, Dict, List, Tuple

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import redact_text, sha256_text, write_json


SENSITIVE_PATTERNS: List[Tuple[str, re.Pattern]] = [
    ("password", re.compile(r"(?i)password\s*[:=]")),
    ("token", re.compile(r"(?i)token\s*[:=]")),
    ("secret", re.compile(r"(?i)secret\s*[:=]")),
    ("api_key", re.compile(r"(?i)api[_-]?key\s*[:=]")),
    ("private_key_block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("ssh_key", re.compile(r"ssh-(rsa|ed25519)\s+[A-Za-z0-9+/=]+")),
]


class SensitiveScannerCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-14-sensitive-scan",
        name="SensitiveScannerCollector",
        version="1.0.0",
        category="security",
        requires_root=False,
        default_enabled=True,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = time.time()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        findings: List[Dict[str, Any]] = []
        redaction_plan: List[Dict[str, Any]] = []

        # Scan only within snapshot (excluding mirror by default for safety/time)
        max_file_bytes = int(ctx.limits.get("sensitive_scan_max_file_bytes", 1024 * 1024))
        max_total_bytes = int(ctx.limits.get("sensitive_scan_max_total_bytes", 10 * 1024 * 1024))
        total_scanned = 0
        files_scanned = 0

        def should_scan(p: Path) -> bool:
            if p.is_dir():
                return False
            if p.suffix.lower() not in {".txt", ".log", ".json", ".conf", ".cfg", ".ini", ".xml", ".html", ".js"}:
                return False
            rel = str(p.relative_to(ctx.snapshot_root))
            if rel.startswith("mirror/"):
                return False
            if rel.startswith("logs/collectors/"):
                # Collector stdout/stderr may contain sensitive info; scan but keep limits.
                return True
            return True

        for p in ctx.snapshot_root.rglob("*"):
            if ctx.should_stop():
                break
            if not should_scan(p):
                continue
            try:
                size = p.stat().st_size
            except Exception:
                continue
            if size > max_file_bytes:
                continue
            if total_scanned + size > max_total_bytes:
                break
            try:
                text = p.read_text(encoding="utf-8", errors="ignore")
            except Exception:
                continue
            total_scanned += size
            files_scanned += 1
            for key, pat in SENSITIVE_PATTERNS:
                if not pat.search(text):
                    continue
                # Create redacted snippet
                snippet = text[:2000]
                snippet = redact_text(snippet, ctx.redaction_level) if ctx.redaction_enabled else snippet
                rel = str(p.relative_to(ctx.snapshot_root))
                item = {
                    "pattern": key,
                    "path": rel,
                    "size_bytes": size,
                    "snippet_redacted": snippet,
                    "risk": "high" if key in {"private_key_block", "ssh_key"} else "medium",
                }
                findings.append(item)
                redaction_plan.append({
                    "path": rel,
                    "action": "redact_in_export" if ctx.research_mode in {"full","extreme"} else "already_redacted_or_stub",
                    "reason": f"Matched sensitive pattern: {key}",
                })
                break

        out_find = ctx.snapshot_root / "security" / "sensitive_findings.json"
        out_plan = ctx.snapshot_root / "security" / "redaction_plan.json"
        out_find.parent.mkdir(parents=True, exist_ok=True)
        write_json(out_find, {"count": len(findings), "files_scanned": files_scanned, "bytes_scanned": total_scanned, "items": findings})
        write_json(out_plan, {"count": len(redaction_plan), "items": redaction_plan})

        # Attach to result
        result["stats"]["items_collected"] = len(findings)
        result["stats"]["files_written"] = 2
        result["stats"]["bytes_written"] = out_find.stat().st_size + out_plan.stat().st_size

        for p, desc in [(out_find, "Sensitive findings report"), (out_plan, "Redaction plan (export)")]:
            result["artifacts"].append({
                "path": str(p.relative_to(ctx.snapshot_root)),
                "type": "json",
                "size_bytes": p.stat().st_size,
                "sha256": None,
                "sensitive": True,
                "redacted": True,
                "description": desc,
            })

        high = sum(1 for i in findings if i["risk"] == "high")
        if high:
            result["findings"].append({
                "severity": "high",
                "code": "high_risk_sensitive_items",
                "title": "High-risk sensitive items detected",
                "details": f"Found {high} high-risk sensitive patterns (keys/certs). Use Export with Redaction before sharing.",
                "refs": [str(out_find.relative_to(ctx.snapshot_root))],
            })

        # Global signals for policy engine
        ctx.signals["security.sensitive_items_count"] = len(findings)
        ctx.signals["security.sensitive_high_count"] = high

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
