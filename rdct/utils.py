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

# Network identifiers often leak internal topology.
_IPV4_RE = re.compile(r"\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b")
_MAC_RE = re.compile(r"\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b")
_IPV6_RE = re.compile(r"\b(?:[0-9A-Fa-f]{1,4}:){2,7}[0-9A-Fa-f]{1,4}\b")


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

    # Network IDs
    def _repl_ipv4(m: re.Match) -> str:
        ip = m.group(0)
        if level == "normal":
            parts = ip.split(".")
            return ".".join(parts[:3] + ["x"]) if len(parts) == 4 else "IP_REDACTED"
        return "IP_REDACTED"

    def _repl_mac(m: re.Match) -> str:
        mac = m.group(0)
        if level == "normal":
            parts = re.split(r"[:-]", mac)
            if len(parts) == 6:
                return ":".join(parts[:3] + ["xx", "xx", "xx"])
        return "MAC_REDACTED"

    out = _MAC_RE.sub(_repl_mac, out)
    out = _IPV4_RE.sub(_repl_ipv4, out)
    # IPv6 is typically fully redacted because partial redaction is error-prone.
    if level in {"strict", "normal"}:
        out = _IPV6_RE.sub("IPV6_REDACTED", out)
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
