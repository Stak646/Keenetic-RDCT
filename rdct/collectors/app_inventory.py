from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import sha256_text, utc_now_iso, write_json


_APP_PATTERNS = [
    ("nfqws", re.compile(r"\bnfqws\b")),
    ("redsocks", re.compile(r"\bredsocks\b")),
    ("dnscrypt-proxy", re.compile(r"\bdnscrypt-proxy\b")),
    ("unbound", re.compile(r"\bunbound\b")),
    ("dnsmasq", re.compile(r"\bdnsmasq\b")),
    ("xray", re.compile(r"\bxray\b|\bv2ray\b")),
    ("sing-box", re.compile(r"\bsing-box\b")),
    ("tor", re.compile(r"\btor\b")),
    ("openvpn", re.compile(r"\bopenvpn\b")),
    ("wireguard", re.compile(r"\bwg\b|\bwireguard\b")),
    ("nginx", re.compile(r"\bnginx\b")),
    ("lighttpd", re.compile(r"\blighttpd\b")),
]


class AppInventoryCollector(BaseCollector):
    META = CollectorMeta(
        name="AppInventoryCollector",
        version="1.0",
        collector_id="ext-10-app-inventory",
        category="apps",
        requires_root=False,
        default_enabled=False,
        risk_level=2,
        cost_level=1,
    )

    def _read_json(self, p: Path) -> Optional[Dict[str, Any]]:
        try:
            if not p.exists():
                return None
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            return None

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = utc_now_iso()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        out_dir = ctx.snapshot_root / "apps"
        out_dir.mkdir(parents=True, exist_ok=True)

        proc_tree = self._read_json(ctx.snapshot_root / "system" / "process_tree.json") or {}
        opkg = self._read_json(ctx.snapshot_root / "apps" / "opkg_installed.json") or {}
        sockets = self._read_json(ctx.snapshot_root / "network" / "listening_ports.json") or {}

        cmdlines: List[str] = []
        processes = proc_tree.get("processes") if isinstance(proc_tree, dict) else None
        if isinstance(processes, list):
            for pr in processes:
                if isinstance(pr, dict):
                    cmdlines.append(str(pr.get("cmdline_redacted") or pr.get("cmdline") or pr.get("name") or ""))

        pkgs: List[str] = []
        if isinstance(opkg, dict) and isinstance(opkg.get("packages"), list):
            for p in opkg["packages"]:
                if isinstance(p, dict) and p.get("name"):
                    pkgs.append(str(p["name"]))

        ports: List[str] = []
        if isinstance(sockets, dict) and isinstance(sockets.get("listening_ports"), list):
            ports = [str(x) for x in sockets.get("listening_ports")]

        evidence_blob = "\n".join(cmdlines + pkgs)

        detected: List[Dict[str, Any]] = []
        for app_id, pat in _APP_PATTERNS:
            if pat.search(evidence_blob):
                detected.append(
                    {
                        "app_id": app_id,
                        "confidence": "heuristic",
                        "evidence": {
                            "process_match": any(pat.search(c) for c in cmdlines),
                            "package_match": any(pat.search(p) for p in pkgs),
                        },
                    }
                )

        inv = {
            "generated_at": utc_now_iso(),
            "detected_apps": detected,
            "installed_packages_count": len(pkgs),
            "listening_ports": ports,
        }
        inv_path = out_dir / "apps_inventory.json"
        write_json(inv_path, inv)

        artifacts = [
            self._register_artifact(
                ctx,
                path=inv_path,
                type_="json",
                sensitive=True,
                redacted=bool(ctx.redaction_enabled),
                description="Derived apps inventory",
                tags=["apps"],
            )
        ]

        # Findings: highlight suspicious combo (proxy-like) if detected.
        proxy_like = {"nfqws", "redsocks", "xray", "sing-box", "tor"}
        found = {d["app_id"] for d in detected if isinstance(d, dict) and d.get("app_id")}
        if found & proxy_like:
            result.setdefault("findings", []).append(
                {
                    "severity": "medium",
                    "code": "proxy_like_apps_detected",
                    "title": "Proxy-like applications detected",
                    "details": f"Detected apps that often participate in traffic redirection/tunneling: {sorted(found & proxy_like)}.",
                    "refs": [{"path": str(inv_path.relative_to(ctx.snapshot_root)), "type": "artifact"}],
                }
            )

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {"apps_inventory_sha256": sha256_text(json.dumps(inv, sort_keys=True))}
        result["stats"]["items_collected"] = len(detected)
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = inv_path.stat().st_size

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
