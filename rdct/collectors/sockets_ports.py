from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import write_json


_SS_LINE_RE = re.compile(r"^(tcp|udp)\s+\S+\s+\S+\s+(\S+):(\d+)\s+\S+\s*(users:\(\([^)]*\)\))?")
_NETSTAT_LINE_RE = re.compile(r"^(tcp|udp)\s+\S+\s+\S+\s+(\S+):(\d+)\s+\S+\s+\S+\s+(\S+)\s*$")


def _parse_users_field(users_field: str) -> Tuple[Optional[int], Optional[str]]:
    # users:(("nginx",pid=123,fd=6))
    if not users_field:
        return None, None
    m = re.search(r'pid=(\d+)', users_field)
    pid = int(m.group(1)) if m else None
    m2 = re.search(r'\(\("([^"]+)"', users_field)
    name = m2.group(1) if m2 else None
    return pid, name


class SocketsPortsCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-08-sockets-ports",
        name="SocketsPortsCollector",
        version="1.0.0",
        category="network",
        requires_root=False,
        default_enabled=True,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = time.time()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        cmd = ["ss", "-lntuap"]
        cr = self._run_cmd(ctx, cmd, timeout_sec=15, sensitive_output=True)
        txt = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore") if cr.stdout_path else ""
        if cr.exit_code == 127 or (not txt.strip()):
            # fallback to netstat
            cmd = ["netstat", "-lntuap"]
            cr = self._run_cmd(ctx, cmd, timeout_sec=15, sensitive_output=True)
            txt = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore") if cr.stdout_path else ""

        entries: List[Dict[str, Any]] = []
        for ln in txt.splitlines():
            ln = ln.strip()
            if not ln or ln.lower().startswith("netid") or ln.lower().startswith("proto"):
                continue
            m = _SS_LINE_RE.match(ln)
            if m:
                proto, host, port_s, users = m.group(1), m.group(2), m.group(3), m.group(4) or ""
                pid, pname = _parse_users_field(users)
                entries.append({
                    "proto": proto,
                    "local": host,
                    "port": int(port_s),
                    "pid": pid,
                    "process": pname,
                    "raw": ln[:500],
                })
                continue
            m2 = _NETSTAT_LINE_RE.match(ln)
            if m2:
                proto, host, port_s, pidprog = m2.group(1), m2.group(2), m2.group(3), m2.group(4)
                pid = None
                pname = None
                if "/" in pidprog:
                    pid_s, pname = pidprog.split("/", 1)
                    if pid_s.isdigit():
                        pid = int(pid_s)
                entries.append({
                    "proto": proto,
                    "local": host,
                    "port": int(port_s),
                    "pid": pid,
                    "process": pname,
                    "raw": ln[:500],
                })

        out = ctx.snapshot_root / "network" / "listening_ports.json"
        write_json(out, {"count": len(entries), "entries": entries})

        result["stats"]["items_collected"] = len(entries)
        result["stats"]["files_written"] = 1
        result["stats"]["bytes_written"] = out.stat().st_size
        result["artifacts"].append({
            "path": str(out.relative_to(ctx.snapshot_root)),
            "type": "json",
            "size_bytes": out.stat().st_size,
            "sha256": None,
            "sensitive": True,  # can include process names / args (raw)
            "redacted": bool(ctx.redaction_enabled and ctx.research_mode in {"light","medium"}),
            "description": "Listening ports inventory (port→pid best-effort)",
        })

        result["normalized_data"] = {
            "listening_ports": sorted({f"{e['proto']}:{e['local']}:{e['port']}" for e in entries}),
        }

        ctx.signals["network.listening_ports"] = result["normalized_data"]["listening_ports"]
        ctx.signals["network.listening_ports_count"] = len(result["normalized_data"]["listening_ports"])

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
