from __future__ import annotations

import dataclasses
import hashlib
import json
import os
import re
import secrets
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, Optional, Tuple

ISO8601_FMT = "%Y-%m-%dT%H:%M:%S.%fZ"


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime(ISO8601_FMT)


def stable_json_dumps(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, indent=2)


def write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(stable_json_dumps(obj) + "\n", encoding="utf-8")


def sha256_file(path: Path, chunk_size: int = 1024 * 1024) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(chunk_size)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", errors="ignore")).hexdigest()


def gen_token(nbytes: int = 24) -> str:
    # URL-safe token for WebUI/API auth.
    return secrets.token_urlsafe(nbytes)


_REDACTION_PATTERNS: Tuple[Tuple[re.Pattern, str], ...] = (
    # generic key-value
    (re.compile(r"(?i)(password\s*[:=]\s*)([^\s'\"\\]+)"), r"\1REDACTED"),
    (re.compile(r"(?i)(passwd\s*[:=]\s*)([^\s'\"\\]+)"), r"\1REDACTED"),
    (re.compile(r"(?i)(token\s*[:=]\s*)([^\s'\"\\]+)"), r"\1REDACTED"),
    (re.compile(r"(?i)(secret\s*[:=]\s*)([^\s'\"\\]+)"), r"\1REDACTED"),
    (re.compile(r"(?i)(api[_-]?key\s*[:=]\s*)([^\s'\"\\]+)"), r"\1REDACTED"),
    # Bearer tokens
    (re.compile(r"(?i)(Authorization:\s*Bearer\s+)([^\s]+)"), r"\1REDACTED"),
    # cookies
    (re.compile(r"(?i)(Set-Cookie:\s*)(.+)"), r"\1REDACTED"),
)


def redact_text(text: str, level: str = "strict") -> str:
    """
    Best-effort redaction for Light/Medium modes.

    level: 'strict'|'normal'|'off'
    """
    if level == "off":
        return text
    out = text
    for pat, repl in _REDACTION_PATTERNS:
        out = pat.sub(repl, out)
    if level == "strict":
        # remove potential private keys blocks
        out = re.sub(r"-----BEGIN [A-Z ]+PRIVATE KEY-----.*?-----END [A-Z ]+PRIVATE KEY-----",
                     "-----BEGIN PRIVATE KEY-----\nREDACTED\n-----END PRIVATE KEY-----",
                     out, flags=re.S)
    return out


def is_root() -> bool:
    try:
        return os.geteuid() == 0
    except AttributeError:
        return False


def ensure_relpath(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except Exception:
        # fallback: normalize without leaking absolute paths too much
        return str(path).lstrip("/")


@dataclasses.dataclass
class CommandResult:
    command: str
    exit_code: int
    stdout_path: Optional[str] = None
    stderr_path: Optional[str] = None
    duration_ms: Optional[int] = None


def human_bytes(n: int) -> str:
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    x = float(n)
    for u in units:
        if x < 1024.0 or u == units[-1]:
            return f"{x:.1f} {u}" if u != "B" else f"{int(x)} B"
        x /= 1024.0
    return f"{n} B"
