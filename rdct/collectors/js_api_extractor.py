from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import sha256_text, utc_now_iso, write_json


_FETCH_RE = re.compile(r"\bfetch\(\s*['\"]([^'\"]+)['\"]")
_AXIOS_RE = re.compile(r"\baxios\.(get|post|put|delete)\(\s*['\"]([^'\"]+)['\"]")
_WS_RE = re.compile(r"\bnew\s+WebSocket\(\s*['\"]([^'\"]+)['\"]")
_XHR_RE = re.compile(r"\.open\(\s*['\"](GET|POST|PUT|DELETE)['\"]\s*,\s*['\"]([^'\"]+)['\"]")


class JSApiExtractorCollector(BaseCollector):
    META = CollectorMeta(
        name="JSApiExtractorCollector",
        version="1.0",
        collector_id="ext-16-js-api-extractor",
        category="web",
        requires_root=False,
        default_enabled=False,
        risk_level=2,
        cost_level=1,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = utc_now_iso()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        bodies_dir = ctx.snapshot_root / "web" / "http_bodies"
        out_dir = ctx.snapshot_root / "web"
        out_dir.mkdir(parents=True, exist_ok=True)

        endpoints: List[Dict[str, Any]] = []
        combined: List[str] = []

        if bodies_dir.exists():
            files = sorted([p for p in bodies_dir.glob("*.html") if p.is_file()])[:50]
            for p in files:
                try:
                    text = p.read_text(encoding="utf-8", errors="ignore")
                except Exception:
                    continue
                combined.append(text)
                for m in _FETCH_RE.finditer(text):
                    endpoints.append({"source": str(p.relative_to(ctx.snapshot_root)), "type": "fetch", "method": None, "url": m.group(1)})
                for m in _AXIOS_RE.finditer(text):
                    endpoints.append({"source": str(p.relative_to(ctx.snapshot_root)), "type": "axios", "method": m.group(1).upper(), "url": m.group(2)})
                for m in _WS_RE.finditer(text):
                    endpoints.append({"source": str(p.relative_to(ctx.snapshot_root)), "type": "websocket", "method": None, "url": m.group(1)})
                for m in _XHR_RE.finditer(text):
                    endpoints.append({"source": str(p.relative_to(ctx.snapshot_root)), "type": "xhr", "method": m.group(1).upper(), "url": m.group(2)})

        # Deduplicate (source+type+method+url)
        seen = set()
        dedup: List[Dict[str, Any]] = []
        for e in endpoints:
            key = (e.get("type"), e.get("method"), e.get("url"))
            if key in seen:
                continue
            seen.add(key)
            dedup.append(e)

        report = {
            "generated_at": utc_now_iso(),
            "endpoints_count": len(dedup),
            "endpoints": dedup,
        }
        out_path = out_dir / "js_api_endpoints.json"
        write_json(out_path, report)

        artifacts = [
            self._register_artifact(
                ctx,
                path=out_path,
                type_="json",
                sensitive=True,
                redacted=bool(ctx.redaction_enabled),
                description="Extracted API endpoints from captured HTML/JS",
                tags=["web", "js"],
            )
        ]

        if not dedup:
            result["run"]["status"] = "partial"

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {"js_api_endpoints_count": report.get("endpoints_count")}
        result["stats"]["items_collected"] = int(report.get("endpoints_count") or 0)
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = out_path.stat().st_size

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
