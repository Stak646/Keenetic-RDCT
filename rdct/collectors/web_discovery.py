from __future__ import annotations

import http.client
import re
import socket
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import redact_text, sha256_text, write_json


def _http_probe(host: str, port: int, timeout: float = 2.0) -> Dict[str, Any]:
    conn = http.client.HTTPConnection(host, port, timeout=timeout)
    try:
        conn.request("GET", "/")
        resp = conn.getresponse()
        body = resp.read(64 * 1024)  # cap
        headers = {k: v for (k, v) in resp.getheaders()}
        return {
            "ok": True,
            "status": resp.status,
            "reason": resp.reason,
            "headers": headers,
            "body_sample": body.decode("utf-8", errors="ignore"),
        }
    except Exception as e:
        return {"ok": False, "error": str(e)}
    finally:
        try:
            conn.close()
        except Exception:
            pass


_TITLE_RE = re.compile(r"(?is)<title[^>]*>(.*?)</title>")


class WebDiscoveryCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-13-web-discovery",
        name="WebDiscoveryCollector",
        version="1.0.0",
        category="web",
        requires_root=False,
        default_enabled=True,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = time.time()
        result = self._result_template(ctx, status="skipped")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        net_policy = ctx.signals.get("config.modes.network_policy", {})
        local_scan_allowed = bool(net_policy.get("local_scan_allowed", True))
        web_probe_allowed = bool(net_policy.get("web_probe_allowed", False))

        # Gate: Respect web_probe_allowed for all modes.
        if not web_probe_allowed:
            result["run"]["status"] = "skipped"
            result["findings"].append({
                "severity": "info",
                "code": "web_probe_disabled",
                "title": "Web probes disabled",
                "details": "Enable modes.network_policy.web_probe_allowed to allow local HTTP probing.",
                "refs": [],
            })
            self._finalize_result(ctx, result, started)
            self.write_result_json(ctx, result)
            self.write_errors_json(ctx, errors, warnings)
            return result

        if not local_scan_allowed:
            result["run"]["status"] = "skipped"
            self._finalize_result(ctx, result, started)
            self.write_result_json(ctx, result)
            self.write_errors_json(ctx, errors, warnings)
            return result

        ports = ctx.signals.get("network.listening_ports", [])
        # Extract unique port numbers.
        port_nums = []
        for s in ports:
            try:
                proto, host, port_s = s.split(":", 2)
                if proto != "tcp":
                    continue
                port = int(port_s)
                if port not in port_nums:
                    port_nums.append(port)
            except Exception:
                continue

        endpoints: List[Dict[str, Any]] = []
        headers_dir = ctx.snapshot_root / "web" / "http_headers"
        bodies_dir = ctx.snapshot_root / "web" / "http_bodies"
        headers_dir.mkdir(parents=True, exist_ok=True)
        bodies_dir.mkdir(parents=True, exist_ok=True)

        for port in port_nums[:40]:
            if ctx.should_stop():
                break
            probe = _http_probe("127.0.0.1", port, timeout=2.0)
            if not probe.get("ok"):
                continue
            body = probe.get("body_sample", "")
            title = None
            m = _TITLE_RE.search(body)
            if m:
                title = m.group(1).strip()[:200]
            headers = probe.get("headers", {})
            banner = headers.get("Server")
            favicon_hash = sha256_text(headers.get("Content-Type","") + headers.get("Server","") + body[:2048])
            endpoint = {
                "url": f"http://127.0.0.1:{port}/",
                "port": port,
                "status": probe.get("status"),
                "title": title,
                "server_banner": banner,
                "favicon_hash": favicon_hash,
                "has_set_cookie": "Set-Cookie" in {k.title(): v for k,v in headers.items()} or any(k.lower() == "set-cookie" for k in headers.keys()),
            }
            # Redact cookies / sensitive header values in light/medium
            if ctx.redaction_enabled and ctx.research_mode in {"light","medium"}:
                safe_headers = {}
                for k, v in headers.items():
                    if k.lower() in {"set-cookie", "cookie", "authorization"}:
                        safe_headers[k] = "REDACTED"
                    else:
                        safe_headers[k] = v
                headers = safe_headers

            hpath = headers_dir / f"{port}.json"
            write_json(hpath, {"url": endpoint["url"], "headers": headers, "status": probe.get("status"), "reason": probe.get("reason")})
            endpoint["headers_ref"] = str(hpath.relative_to(ctx.snapshot_root))

            # Save HTML/body sample (redacted in Light/Medium)
            if ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}:
                body = redact_text(body, ctx.redaction_level)
            body_path = bodies_dir / f"{port}.html"
            body_path.write_text(body, encoding="utf-8", errors="ignore")
            endpoint["body_ref"] = str(body_path.relative_to(ctx.snapshot_root))
            endpoints.append(endpoint)

            # findings: admin panels (heuristic)
            if title and any(x in title.lower() for x in ["admin", "login", "panel", "router", "keenetic"]):
                result["findings"].append({
                    "severity": "medium",
                    "code": "possible_admin_ui",
                    "title": "Possible admin web interface detected",
                    "details": f"Local HTTP service on port {port} looks like an admin/login panel (heuristic).",
                    "refs": [endpoint["headers_ref"]],
                })

        inv_path = ctx.snapshot_root / "web" / "endpoints_inventory.json"
        write_json(inv_path, {"count": len(endpoints), "endpoints": endpoints})

        result["run"]["status"] = "success"
        result["stats"]["items_collected"] = len(endpoints)
        result["stats"]["files_written"] = 1 + (2 * len(endpoints))
        result["stats"]["bytes_written"] = inv_path.stat().st_size + sum((ctx.snapshot_root / e["headers_ref"]).stat().st_size for e in endpoints) + sum((ctx.snapshot_root / e["body_ref"]).stat().st_size for e in endpoints)

        # Inventory + per-endpoint headers/body samples
        result["artifacts"].append(self._register_artifact(
            ctx,
            path=inv_path,
            type_="json",
            sensitive=True,
            redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
            description="Discovered local HTTP endpoints inventory",
            tags=["web", "discovery"],
        ))

        for e in endpoints:
            hp = ctx.snapshot_root / e["headers_ref"]
            bp = ctx.snapshot_root / e["body_ref"]
            result["artifacts"].append(self._register_artifact(
                ctx,
                path=hp,
                type_="json",
                sensitive=True,
                redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                description=f"HTTP headers sample for port {e['port']}",
                tags=["web", "headers"],
            ))
            result["artifacts"].append(self._register_artifact(
                ctx,
                path=bp,
                type_="text",
                sensitive=True,
                redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                description=f"HTTP body sample for port {e['port']} (truncated)",
                tags=["web", "body"],
            ))

        result["normalized_data"] = {"http_endpoints": sorted([e["url"] for e in endpoints])}
        ctx.signals["web.endpoints"] = result["normalized_data"]["http_endpoints"]

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
