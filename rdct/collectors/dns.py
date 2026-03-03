from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import redact_text, sha256_text, utc_now_iso, write_json


class DNSCollector(BaseCollector):
    META = CollectorMeta(
        name="DNSCollector",
        version="1.0",
        collector_id="ext-03-dns",
        category="network",
        requires_root=False,
        default_enabled=False,
        risk_level=2,
        cost_level=1,
    )

    def _copy_text_file(self, ctx: CollectorContext, src: Path, dst_rel: str, *, sensitive: bool) -> Optional[Path]:
        try:
            if not src.exists() or not src.is_file():
                return None
            text = src.read_text(encoding="utf-8", errors="ignore")
            return self._write_text(ctx, dst_rel, text, sensitive=sensitive)
        except Exception:
            return None

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = utc_now_iso()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        out_dir = ctx.snapshot_root / "network" / "dns"
        out_dir.mkdir(parents=True, exist_ok=True)

        candidates: List[Path] = [
            Path("/etc/resolv.conf"),
            Path("/etc/hosts"),
            Path("/etc/dnsmasq.conf"),
            Path("/etc/unbound/unbound.conf"),
            Path("/tmp/resolv.conf"),
            Path("/tmp/dnsmasq.conf"),
            Path("/opt/etc/dnsmasq.conf"),
            Path("/opt/etc/unbound/unbound.conf"),
        ]

        # Directories
        dir_candidates: List[Path] = [
            Path("/etc/dnsmasq.d"),
            Path("/opt/etc/dnsmasq.d"),
            Path("/etc/unbound"),
            Path("/opt/etc/unbound"),
        ]

        artifacts = []
        collected_paths: List[str] = []
        combined_texts: List[str] = []

        for src in candidates:
            dst_rel = str((out_dir / src.name).relative_to(ctx.snapshot_root))
            p = self._copy_text_file(ctx, src, dst_rel, sensitive=True)
            if p:
                collected_paths.append(str(src))
                combined_texts.append(p.read_text(encoding="utf-8", errors="ignore"))
                artifacts.append(self._register_artifact(
                    ctx,
                    path=p,
                    type_="text",
                    sensitive=True,
                    redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                    description=f"DNS config copy of {src}",
                    tags=["dns"],
                ))

        # Copy a limited set of files from dnsmasq/unbound dirs (depth 1, up to 50 files)
        for d in dir_candidates:
            if not d.exists() or not d.is_dir():
                continue
            try:
                files = sorted([p for p in d.iterdir() if p.is_file()])[:50]
            except Exception:
                continue
            for src in files:
                rel = str((out_dir / d.name / src.name).relative_to(ctx.snapshot_root))
                p = self._copy_text_file(ctx, src, rel, sensitive=True)
                if p:
                    collected_paths.append(str(src))
                    combined_texts.append(p.read_text(encoding="utf-8", errors="ignore"))
                    artifacts.append(self._register_artifact(
                        ctx,
                        path=p,
                        type_="text",
                        sensitive=True,
                        redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                        description=f"DNS config copy of {src}",
                        tags=["dns"],
                    ))

        combined = "\n\n".join(combined_texts)
        # Extract upstream nameservers (best-effort)
        upstream: List[str] = []
        try:
            for ln in combined.splitlines():
                s = ln.strip()
                if s.startswith("nameserver "):
                    upstream.append(s.split(None, 1)[1])
        except Exception:
            upstream = []

        summary = {
            "collected_source_paths": collected_paths,
            "upstream_nameservers": sorted(set(upstream))[:20],
            "combined_sha256": sha256_text(combined) if combined else None,
        }
        sum_path = out_dir / "dns_summary.json"
        write_json(sum_path, summary)
        artifacts.append(self._register_artifact(
            ctx,
            path=sum_path,
            type_="json",
            sensitive=False,
            redacted=False,
            description="DNS summary",
            tags=["dns"],
        ))

        if not collected_paths:
            result["run"]["status"] = "partial"
            result.setdefault("findings", []).append(
                {
                    "severity": "info",
                    "code": "dns_no_files",
                    "title": "DNS configuration files not found",
                    "details": "No DNS-related configuration files were collected from common locations.",
                    "refs": [{"path": str(sum_path.relative_to(ctx.snapshot_root)), "type": "artifact"}],
                }
            )

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {
            "dns_upstream_nameservers": summary.get("upstream_nameservers"),
            "dns_config_sha256": summary.get("combined_sha256"),
        }
        result["stats"]["items_collected"] = len(collected_paths)
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = sum((ctx.snapshot_root / a["path"]).stat().st_size for a in artifacts if a.get("path"))

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
