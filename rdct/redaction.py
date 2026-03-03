from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, Tuple

from .utils import redact_text, stable_json_dumps


SENSITIVE_KEY_RE = re.compile(r"(?i)(pass(word)?|passwd|token|secret|api[_-]?key|cookie|authorization|session)")


@dataclass
class RedactionPolicy:
    enabled: bool = True
    level: str = "strict"  # strict|normal|off


def redact_json_obj(obj: Any, level: str) -> Any:
    """Recursively redact a JSON-like object.

    We deliberately keep structure stable and only replace sensitive values.
    """
    if level == "off":
        return obj
    if isinstance(obj, dict):
        out: Dict[str, Any] = {}
        for k, v in obj.items():
            if SENSITIVE_KEY_RE.search(str(k) or ""):
                # Keep type stable-ish.
                if isinstance(v, (dict, list)):
                    out[k] = "REDACTED"
                else:
                    out[k] = "REDACTED"
            else:
                out[k] = redact_json_obj(v, level)
        return out
    if isinstance(obj, list):
        return [redact_json_obj(x, level) for x in obj]
    if isinstance(obj, str):
        return redact_text(obj, level)
    return obj


def redact_file_to(src: Path, dst: Path, *, level: str) -> Tuple[bool, str]:
    """Redact a file into dst.

    Returns: (ok, note)
    """
    dst.parent.mkdir(parents=True, exist_ok=True)

    # Heuristic: treat small files as text-ish, JSON separately.
    suffix = src.suffix.lower()
    try:
        if suffix == ".json":
            data = json.loads(src.read_text(encoding="utf-8", errors="ignore"))
            data = redact_json_obj(data, level)
            dst.write_text(stable_json_dumps(data) + "\n", encoding="utf-8")
            return True, "json_redacted"

        # Text-like extensions
        if suffix in {".txt", ".log", ".conf", ".cfg", ".ini", ".sh", ".md", ".csv"}:
            dst.write_text(redact_text(src.read_text(encoding="utf-8", errors="ignore"), level), encoding="utf-8")
            return True, "text_redacted"

        # Unknown: try decode as utf-8 if small
        if src.stat().st_size <= 2 * 1024 * 1024:
            raw = src.read_bytes()
            try:
                text = raw.decode("utf-8")
                dst.write_text(redact_text(text, level), encoding="utf-8")
                return True, "heuristic_text_redacted"
            except Exception:
                pass

        # Binary or large: copy as-is in normal/off, stub in strict.
        if level == "strict":
            dst.write_text(
                "REDACTED_BINARY_OR_LARGE\n"
                f"source_name={src.name}\n"
                f"size_bytes={src.stat().st_size}\n",
                encoding="utf-8",
            )
            return True, "stubbed_binary"
        dst.write_bytes(src.read_bytes())
        return True, "copied_binary"
    except Exception as e:
        # As a last resort, copy as-is to keep export consistent.
        try:
            dst.write_bytes(src.read_bytes())
            return False, f"redaction_failed_copied:{e}"
        except Exception as e2:
            return False, f"redaction_failed:{e};copy_failed:{e2}"
