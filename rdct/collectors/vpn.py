from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import sha256_text, utc_now_iso, write_json


class VPNCollector(BaseCollector):
    META = CollectorMeta(
        name="VPNCollector",
        version="1.0",
        collector_id="ext-06-vpn",
        category="network",
        requires_root=False,
        default_enabled=False,
        risk_level=3,
        cost_level=2,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = utc_now_iso()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        out_dir = ctx.snapshot_root / "network" / "vpn"
        out_dir.mkdir(parents=True, exist_ok=True)

        artifacts = []
        texts: List[str] = []

        # WireGuard status
        for cmd, fname, desc in [
            (["wg", "show", "all"], "wg_show.txt", "wg show all"),
            (["ip", "link", "show", "type", "wireguard"], "ip_link_wireguard.txt", "ip link show type wireguard"),
            (["openvpn", "--version"], "openvpn_version.txt", "openvpn --version"),
        ]:
            try:
                cr = self._run_cmd(ctx, cmd, timeout_sec=int(ctx.limits.get("collector_timeout_sec", 30)), sensitive_output=True)
                text = ""
                if cr.stdout_path and Path(cr.stdout_path).exists():
                    text = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore")
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
                    tags=["vpn"],
                ))
            except Exception:
                continue

        # Config files (WireGuard/OpenVPN)
        for base in [Path("/etc/wireguard"), Path("/opt/etc/wireguard"), Path("/etc/openvpn"), Path("/opt/etc/openvpn")]:
            if not base.exists() or not base.is_dir():
                continue
            try:
                files = sorted([p for p in base.rglob("*") if p.is_file()])[:50]
            except Exception:
                continue
            for src in files:
                try:
                    text = src.read_text(encoding="utf-8", errors="ignore")
                except Exception:
                    continue
                rel = str((out_dir / base.name / src.name).relative_to(ctx.snapshot_root))
                p = self._write_text(ctx, rel, text, sensitive=True)
                texts.append(text)
                artifacts.append(self._register_artifact(
                    ctx,
                    path=p,
                    type_="text",
                    sensitive=True,
                    redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                    description=f"VPN config copy of {src}",
                    tags=["vpn"],
                ))

        summary = {
            "collected": bool(artifacts),
            "combined_sha256": sha256_text("\n".join(texts)) if texts else None,
        }
        sum_path = out_dir / "vpn_summary.json"
        write_json(sum_path, summary)
        artifacts.append(self._register_artifact(
            ctx,
            path=sum_path,
            type_="json",
            sensitive=False,
            redacted=False,
            description="VPN summary",
            tags=["vpn"],
        ))

        if not texts:
            result["run"]["status"] = "partial"
            result.setdefault("findings", []).append(
                {
                    "severity": "info",
                    "code": "vpn_unavailable",
                    "title": "VPN info not collected",
                    "details": "No VPN status output or configuration files were collected (tools not installed or directories absent).",
                    "refs": [{"path": str(sum_path.relative_to(ctx.snapshot_root)), "type": "artifact"}],
                }
            )

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {"vpn_sha256": summary.get("combined_sha256")}
        result["stats"]["items_collected"] = len(texts)
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = sum((ctx.snapshot_root / a["path"]).stat().st_size for a in artifacts if a.get("path"))

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
