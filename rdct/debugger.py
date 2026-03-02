from __future__ import annotations

import json
import platform
import traceback
from pathlib import Path
from typing import Any, Dict, Optional

from .utils import utc_now_iso, stable_json_dumps


def write_crash_report(crash_dir: Path, exc: BaseException, context: Optional[Dict[str, Any]] = None) -> Path:
    crash_dir.mkdir(parents=True, exist_ok=True)
    report = {
        "crash_report_version": "1.0.0",
        "time": utc_now_iso(),
        "exception": {
            "type": type(exc).__name__,
            "message": str(exc),
            "traceback": traceback.format_exc(),
        },
        "platform": {
            "python": platform.python_version(),
            "system": platform.system(),
            "machine": platform.machine(),
        },
        "context": context or {},
    }
    fname = f"crash_{report['time'].replace(':','').replace('.','')}.json"
    out = crash_dir / fname
    out.write_text(stable_json_dumps(report) + "\n", encoding="utf-8")
    return out
