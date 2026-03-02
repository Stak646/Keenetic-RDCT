from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import Optional


def setup_logging(log_file: Path, level: str = "INFO") -> logging.Logger:
    log_file.parent.mkdir(parents=True, exist_ok=True)

    logger = logging.getLogger("rdct")
    if logger.handlers:
        return logger

    lvl = getattr(logging, level.upper(), logging.INFO)
    logger.setLevel(lvl)

    fmt = logging.Formatter(
        fmt="%(asctime)s %(levelname)s %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    fh = logging.FileHandler(log_file, encoding="utf-8")
    fh.setLevel(lvl)
    fh.setFormatter(fmt)
    logger.addHandler(fh)

    sh = logging.StreamHandler()
    sh.setLevel(lvl)
    sh.setFormatter(fmt)
    logger.addHandler(sh)

    # Reduce noise from stdlib HTTP server
    logging.getLogger("http.server").setLevel(logging.WARNING)
    logging.getLogger("socketserver").setLevel(logging.WARNING)

    return logger
