from __future__ import annotations

import os
import re
import time
from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import sha256_text, utc_now_iso, write_json


def parse_cpuinfo_text(cpuinfo: str) -> Dict[str, object]:
    """Best-effort CPU info for embedded Linux."""
    cpu: Dict[str, object] = {"model": None, "cores": None, "features": None}
    if not cpuinfo:
        return cpu
    lines = cpuinfo.splitlines()

    cores = 0
    for ln in lines:
        if ln.lower().startswith("processor") and ":" in ln:
            cores += 1
    cpu["cores"] = cores or None

    model = None
    for key in ("model name", "hardware", "system type", "cpu model"):
        for ln in lines:
            if ln.lower().startswith(key) and ":" in ln:
                model = ln.split(":", 1)[1].strip()
                break
        if model:
            break
    cpu["model"] = model

    feats = None
    for ln in lines:
        if ln.lower().startswith("features") and ":" in ln:
            feats = ln.split(":", 1)[1].strip()
            break
    cpu["features"] = feats

    return cpu


class DeviceInfoCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-01-device-info",
        name="DeviceInfoCollector",
        version="1.0.0",
        category="device",
        requires_root=False,
        default_enabled=True,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = time.time()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        # uname
        uname = ""
        try:
            cr = self._run_cmd(ctx, ["uname", "-a"])
            uname = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore") if cr.stdout_path else ""
        except Exception as e:
            warnings.append({"time": utc_now_iso(), "level": "warning", "code": "uname_failed", "message": str(e)})

        # cpuinfo / meminfo
        cpuinfo = ""
        meminfo = ""
        try:
            cpuinfo = Path("/proc/cpuinfo").read_text(encoding="utf-8", errors="ignore")
        except Exception:
            pass
        try:
            meminfo = Path("/proc/meminfo").read_text(encoding="utf-8", errors="ignore")
        except Exception:
            pass

        # parse memory total/available
        total_kb = None
        avail_kb = None
        for line in meminfo.splitlines():
            if line.startswith("MemTotal:"):
                m = re.search(r"(\d+)", line)
                if m:
                    total_kb = int(m.group(1))
            if line.startswith("MemAvailable:"):
                m = re.search(r"(\d+)", line)
                if m:
                    avail_kb = int(m.group(1))

        arch = "unknown"
        m = re.search(r"\b(mipsel|mips|aarch64)\b", uname)
        if m:
            arch = m.group(1)
        else:
            # fallback to uname -m
            try:
                cr2 = self._run_cmd(ctx, ["uname", "-m"])
                um = Path(cr2.stdout_path).read_text(encoding="utf-8", errors="ignore").strip()
                if "aarch64" in um or "arm64" in um:
                    arch = "aarch64"
                elif "mipsel" in um:
                    arch = "mipsel"
                elif "mips" in um:
                    arch = "mips"
            except Exception:
                pass

        model = "unknown"
        # Keenetic model often available via /proc/device-tree/model (if present)
        for candidate in ["/proc/device-tree/model", "/sys/firmware/devicetree/base/model"]:
            try:
                model = Path(candidate).read_text(encoding="utf-8", errors="ignore").strip("\x00\n ")
                if model:
                    break
            except Exception:
                pass

        uptime_seconds = None
        try:
            up = Path("/proc/uptime").read_text(encoding="utf-8", errors="ignore").split()[0]
            uptime_seconds = int(float(up))
        except Exception:
            pass

        mem_total_bytes = int(total_kb * 1024) if total_kb is not None else None
        mem_avail_bytes = int(avail_kb * 1024) if avail_kb is not None else None

        device_info = {
            "collected_at": utc_now_iso(),
            "hostname": socket.gethostname(),
            "vendor": "Keenetic",
            "model": model or None,
            "arch": arch,
            "architecture": arch,
            "kernel": getattr(os.uname(), "release", None),
            "cpu": parse_cpuinfo_text(cpuinfo),
            "uname": uname.strip(),
            "cpuinfo_sha256": sha256_text(cpuinfo) if cpuinfo else None,
            # Keep both flat and nested memory fields for compatibility
            "mem_total_bytes": mem_total_bytes,
            "mem_available_bytes": mem_avail_bytes,
            "memory": {
                "total_bytes": mem_total_bytes,
                "available_bytes": mem_avail_bytes,
            },
            "uptime_seconds": uptime_seconds,
        }

        out_path = ctx.snapshot_root / "device" / "device_info.json"
        write_json(out_path, device_info)

        result["stats"]["items_collected"] = 1
        result["stats"]["files_written"] = 1
        result["stats"]["bytes_written"] = out_path.stat().st_size
        result["artifacts"].append(self._register_artifact(
            ctx,
            path=out_path,
            type_="json",
            sensitive=False,
            redacted=False,
            description="Basic device information",
            tags=["device"],
        ))
        result["normalized_data"] = {
            "device_signature": sha256_text(f"{model}|{arch}|{device_info.get('uname','')}"),
        }

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        # Provide signals
        ctx.signals["device.architecture"] = arch
        ctx.signals["device.model"] = model
        if device_info["memory"]["available_bytes"] is not None:
            ctx.signals["system.mem_available_bytes"] = device_info["memory"]["available_bytes"]
        return result
