"""Allowlist App Manager (optional).

This package provides catalog-driven installation/update helpers for a small, allowlisted
set of known projects.

All operations are explicit user actions (CLI/API) and require Entware (/opt) on USB.
"""

from .manager import AppManager, AppManagerError, AppStatus

__all__ = ["AppManager", "AppManagerError", "AppStatus"]
