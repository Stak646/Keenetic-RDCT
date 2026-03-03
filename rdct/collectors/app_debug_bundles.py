from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import utc_now_iso, write_json


_APP_PATHS: Dict[str, List[Path]] = {
    "nginx": [Path("/opt/etc/nginx"), Path("/etc/nginx"), Path("/opt/var/log/nginx"), Path("/var/log/nginx")],
    "dnsmasq": [Path("/opt/etc/dnsmasq.conf"), Path("/etc/dnsmasq.conf"), Path("/opt/etc/dnsmasq.d"), Path("/etc/dnsmasq.d")],
    "unbound": [Path("/opt/etc/unbound"), Path("/etc/unbound")],
    "xray": [Path("/opt/etc/xray"), Path("/etc/xray")],
    "sing-box": [Path("/opt/etc/sing-box"), Path("/etc/sing-box")],
    "nfqws": [Path("/opt/etc/nfqws"), Path("/etc/nfqws")],

    # Allowlist apps (TZ): best-effort common paths on Keenetic/Entware
    "nfqws2-keenetic": [
        Path("/opt/etc/nfqws2"),
        Path("/etc/nfqws2"),
        Path("/opt/etc/init.d/S51nfqws2"),
        Path("/opt/var/log/nfqws2"),
        Path("/opt/var/log/nfqws2.log"),
    ],
    "nfqws-keenetic-web": [
        Path("/opt/etc/nfqws-web"),
        Path("/opt/etc/nfqws_web"),
        Path("/opt/etc/init.d/S52nfqws-web"),
        Path("/opt/var/log/nfqws-web"),
        Path("/opt/var/log/nfqws-web.log"),
        Path("/opt/var/www/nfqws"),
        Path("/opt/var/www/nfqws-web"),
    ],
    "hydraroute": [
        Path("/opt/etc/hydraroute"),
        Path("/etc/hydraroute"),
        Path("/opt/etc/init.d/S99hydraroute"),
        Path("/opt/var/log/hydraroute"),
        Path("/opt/var/log/hydraroute.log"),
    ],
    "magitrickle": [
        Path("/opt/etc/magitrickle"),
        Path("/etc/magitrickle"),
        Path("/opt/etc/init.d/S99magitrickle"),
        Path("/opt/var/log/magitrickle"),
        Path("/opt/var/log/magitrickle.log"),
    ],
    "awg-manager": [
        Path("/opt/etc/awg-manager"),
        Path("/opt/etc/awg_manager"),
        Path("/opt/etc/init.d/S99awg-manager"),
        Path("/opt/var/log/awg-manager"),
        Path("/opt/var/log/awg-manager.log"),
        Path("/opt/var/log/awg-manager-error.log"),
    ],
}


class AppDebugBundlesCollector(BaseCollector):
    META = CollectorMeta(
        name="AppDebugBundlesCollector",
        version="1.0",
        collector_id="ext-11-app-debug-bundles",
        category="apps",
        requires_root=False,
        default_enabled=False,
        risk_level=3,
        cost_level=3,
    )

    def _read_json(self, p: Path) -> Optional[Dict[str, Any]]:
        try:
            if not p.exists():
                return None
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            return None

    def _copy_file_tail(self, ctx: CollectorContext, src: Path, dst_rel: str, *, max_lines: int = 2000) -> Optional[Path]:
        try:
            if not src.exists() or not src.is_file():
                return None
            lines = src.read_text(encoding="utf-8", errors="ignore").splitlines()[-max_lines:]
            return self._write_text(ctx, dst_rel, "\n".join(lines) + "\n", sensitive=True)
        except Exception:
            return None

    def _copy_file_full(self, ctx: CollectorContext, src: Path, dst_rel: str, *, max_bytes: int = 512 * 1024) -> Optional[Path]:
        try:
            if not src.exists() or not src.is_file():
                return None
            data = src.read_bytes()
            if len(data) > max_bytes:
                data = data[:max_bytes]
            # Write as text if decodable; else hex fallback
            try:
                txt = data.decode("utf-8", errors="ignore")
            except Exception:
                txt = ""
            return self._write_text(ctx, dst_rel, txt, sensitive=True)
        except Exception:
            return None

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = utc_now_iso()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        inv = self._read_json(ctx.snapshot_root / "apps" / "apps_inventory.json") or {}
        detected = inv.get("detected_apps") if isinstance(inv, dict) else []
        app_ids: List[str] = []
        if isinstance(detected, list):
            for d in detected:
                if isinstance(d, dict) and d.get("app_id"):
                    app_ids.append(str(d["app_id"]))

        out_root = ctx.snapshot_root / "apps" / "debug_bundles"
        out_root.mkdir(parents=True, exist_ok=True)

        artifacts = []
        included: Dict[str, List[str]] = {}

        for app_id in sorted(set(app_ids)):
            paths = _APP_PATHS.get(app_id) or []
            if not paths:
                continue
            included.setdefault(app_id, [])
            app_out = out_root / app_id
            app_out.mkdir(parents=True, exist_ok=True)
            for base in paths:
                if not base.exists():
                    continue
                if base.is_file():
                    rel = str((app_out / base.name).relative_to(ctx.snapshot_root))
                    p = self._copy_file_full(ctx, base, rel)
                    if p:
                        included[app_id].append(str(base))
                        artifacts.append(self._register_artifact(
                            ctx,
                            path=p,
                            type_="text",
                            sensitive=True,
                            redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                            description=f"Debug bundle file copy for {app_id}: {base}",
                            tags=["apps", "debug_bundle"],
                        ))
                elif base.is_dir():
                    try:
                        files = sorted([p for p in base.rglob("*") if p.is_file()])[:50]
                    except Exception:
                        files = []
                    for src in files:
                        # Prefer tailing log-like files
                        rel = str((app_out / base.name / src.name).relative_to(ctx.snapshot_root))
                        if any(src.name.endswith(x) for x in [".log", ".txt"]):
                            p = self._copy_file_tail(ctx, src, rel)
                        else:
                            p = self._copy_file_full(ctx, src, rel)
                        if p:
                            included[app_id].append(str(src))
                            artifacts.append(self._register_artifact(
                                ctx,
                                path=p,
                                type_="text",
                                sensitive=True,
                                redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                                description=f"Debug bundle file for {app_id}: {src}",
                                tags=["apps", "debug_bundle"],
                            ))

        report_path = out_root / "debug_bundles.json"
        write_json(report_path, {"generated_at": utc_now_iso(), "included": included})
        artifacts.append(self._register_artifact(
            ctx,
            path=report_path,
            type_="json",
            sensitive=True,
            redacted=bool(ctx.redaction_enabled),
            description="Debug bundles report",
            tags=["apps", "debug_bundle"],
        ))

        if not included:
            result["run"]["status"] = "partial"

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {"debug_bundles_apps": sorted(included.keys())}
        result["stats"]["items_collected"] = sum(len(v) for v in included.values())
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = sum((ctx.snapshot_root / a["path"]).stat().st_size for a in artifacts if a.get("path"))

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
