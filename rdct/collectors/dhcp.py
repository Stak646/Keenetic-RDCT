from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Optional

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import sha256_text, utc_now_iso, write_json


class DHCPCollector(BaseCollector):
    META = CollectorMeta(
        name="DHCPCollector",
        version="1.0",
        collector_id="ext-04-dhcp",
        category="network",
        requires_root=False,
        default_enabled=False,
        risk_level=3,
        cost_level=1,
    )

    def _read_tail(self, src: Path, max_lines: int = 2000) -> Optional[str]:
        try:
            if not src.exists() or not src.is_file():
                return None
            lines = src.read_text(encoding="utf-8", errors="ignore").splitlines()[-max_lines:]
            return "\n".join(lines) + "\n"
        except Exception:
            return None

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = utc_now_iso()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        out_dir = ctx.snapshot_root / "network" / "dhcp"
        out_dir.mkdir(parents=True, exist_ok=True)

        lease_candidates = [
            Path("/var/lib/misc/dnsmasq.leases"),
            Path("/tmp/dnsmasq.leases"),
            Path("/var/lib/dnsmasq/dnsmasq.leases"),
            Path("/opt/var/lib/misc/dnsmasq.leases"),
        ]

        artifacts = []
        collected: List[str] = []
        combined: List[str] = []

        for src in lease_candidates:
            text = self._read_tail(src)
            if not text:
                continue
            rel = str((out_dir / (src.name + ".tail.txt")).relative_to(ctx.snapshot_root))
            p = self._write_text(ctx, rel, text, sensitive=True)
            collected.append(str(src))
            combined.append(text)
            artifacts.append(self._register_artifact(
                ctx,
                path=p,
                type_="text",
                sensitive=True,
                redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                description=f"DHCP leases tail from {src}",
                tags=["dhcp"],
            ))

        summary = {
            "collected_source_paths": collected,
            "combined_sha256": sha256_text("\n".join(combined)) if combined else None,
        }
        sum_path = out_dir / "dhcp_summary.json"
        write_json(sum_path, summary)
        artifacts.append(self._register_artifact(
            ctx,
            path=sum_path,
            type_="json",
            sensitive=False,
            redacted=False,
            description="DHCP summary",
            tags=["dhcp"],
        ))

        if not collected:
            result["run"]["status"] = "partial"
            result.setdefault("findings", []).append(
                {
                    "severity": "info",
                    "code": "dhcp_no_leases",
                    "title": "DHCP leases file not found",
                    "details": "No DHCP leases were collected from common dnsmasq locations.",
                    "refs": [{"path": str(sum_path.relative_to(ctx.snapshot_root)), "type": "artifact"}],
                }
            )

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {"dhcp_leases_sha256": summary.get("combined_sha256")}
        result["stats"]["items_collected"] = len(collected)
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = sum((ctx.snapshot_root / a["path"]).stat().st_size for a in artifacts if a.get("path"))

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
