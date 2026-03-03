from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict


def detect_lang(explicit: str | None = None) -> str:
    """Return 'ru' or 'en'.

    Priority:
      1) explicit argument
      2) RDCT_LANG env
      3) LANG/LC_ALL/LC_MESSAGES
      4) default 'en'
    """
    if explicit:
        v = explicit.strip().lower()
        if v.startswith("ru"):
            return "ru"
        return "en"
    env = (os.environ.get("RDCT_LANG") or "").strip().lower()
    if env:
        return "ru" if env.startswith("ru") else "en"
    for k in ("LC_ALL", "LC_MESSAGES", "LANG"):
        v = (os.environ.get(k) or "").strip().lower()
        if v:
            return "ru" if v.startswith("ru") else "en"
    return "en"


@dataclass(frozen=True)
class I18N:
    lang: str
    strings: Dict[str, str]

    def t(self, key: str, **kwargs: Any) -> str:
        s = self.strings.get(key) or key
        try:
            return s.format(**kwargs)
        except Exception:
            return s


def load_i18n(lang: str, base_dir: Path | None = None) -> I18N:
    """Load translations from rdct/locales/<lang>.json.

    base_dir is expected to be the RDCT package root directory.
    """
    lang = "ru" if str(lang).lower().startswith("ru") else "en"
    here = Path(__file__).resolve().parent
    root = base_dir or here
    loc = root / "locales" / f"{lang}.json"
    fallback = root / "locales" / "en.json"
    data: Dict[str, str] = {}
    for p in (loc, fallback):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
            break
        except Exception:
            continue
    return I18N(lang=lang, strings=data)
