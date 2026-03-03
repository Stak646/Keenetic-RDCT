from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import sha256_text, utc_now_iso, write_json


class WiFiCollector(BaseCollector):
    META = CollectorMeta(
        name="WiFiCollector",
        version="1.0",
        collector_id="ext-05-wifi",
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

        out_dir = ctx.snapshot_root / "network" / "wifi"
        out_dir.mkdir(parents=True, exist_ok=True)

        artifacts = []
        collected_texts: List[str] = []

        for cmd, fname, desc in [
            (["iw", "dev"], "iw_dev.txt", "iw dev"),
            (["iwconfig"], "iwconfig.txt", "iwconfig"),
            (["iw", "link"], "iw_link.txt", "iw link"),
            (["iw", "station", "dump"], "iw_station_dump.txt", "iw station dump"),
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
                collected_texts.append(text)
                artifacts.append(self._register_artifact(
                    ctx,
                    path=p,
                    type_="text",
                    sensitive=True,
                    redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                    description=desc,
                    tags=["wifi"],
                ))
            except Exception:
                continue

        # Try common config paths (do not attempt to capture secrets beyond redaction)
        for src in [
            Path("/etc/hostapd.conf"),
            Path("/etc/config/wireless"),
            Path("/opt/etc/hostapd.conf"),
        ]:
            try:
                if not src.exists() or not src.is_file():
                    continue
                text = src.read_text(encoding="utf-8", errors="ignore")
                rel = str((out_dir / (src.name + ".copy")).relative_to(ctx.snapshot_root))
                p = self._write_text(ctx, rel, text, sensitive=True)
                collected_texts.append(text)
                artifacts.append(self._register_artifact(
                    ctx,
                    path=p,
                    type_="text",
                    sensitive=True,
                    redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                    description=f"Wi-Fi config copy of {src}",
                    tags=["wifi"],
                ))
            except Exception:
                continue

        summary = {
            "collected": bool(artifacts),
            "combined_sha256": sha256_text("\n".join(collected_texts)) if collected_texts else None,
        }
        sum_path = out_dir / "wifi_summary.json"
        write_json(sum_path, summary)
        artifacts.append(self._register_artifact(
            ctx,
            path=sum_path,
            type_="json",
            sensitive=False,
            redacted=False,
            description="Wi-Fi summary",
            tags=["wifi"],
        ))

        if not collected_texts:
            result["run"]["status"] = "partial"
            result.setdefault("findings", []).append(
                {
                    "severity": "info",
                    "code": "wifi_unavailable",
                    "title": "Wi‑Fi info not collected",
                    "details": "No Wi‑Fi command output or config files were collected (missing tools or interfaces).",
                    "refs": [{"path": str(sum_path.relative_to(ctx.snapshot_root)), "type": "artifact"}],
                }
            )

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {"wifi_sha256": summary.get("combined_sha256")}
        result["stats"]["items_collected"] = len(collected_texts)
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = sum((ctx.snapshot_root / a["path"]).stat().st_size for a in artifacts if a.get("path"))

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
