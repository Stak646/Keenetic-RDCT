from __future__ import annotations

import dataclasses
import json
from pathlib import Path
from typing import Any, Dict, Optional

from .utils import gen_token, stable_json_dumps


DEFAULT_CONFIG_VERSION = "1.0.0"


def default_config(base_path: Path) -> Dict[str, Any]:
    return {
        "config_version": DEFAULT_CONFIG_VERSION,
        "language": "ru",
        "storage": {
            "base_path": str(base_path),
        },
        "modes": {
            "research_mode": "light",  # light|medium|full|extreme
            "performance_mode": "auto",  # lite|middle|hard|auto
            "redaction": {
                "enabled": True,
                "level": "strict",  # strict|normal|off
            },
            "mirror_policy": {
                "enabled": False,
                "max_total_bytes": 200 * 1024 * 1024,
                "max_files": 20000,
                "max_depth": 12,
                "max_single_file_bytes": 20 * 1024 * 1024,
                "follow_symlinks": False,
                "include_hidden": False,
                "sample_mode": {
                    "enabled": True,
                    "max_files_per_dir": 200,
                    "tail_threshold_bytes": 512 * 1024,
                    "tail_bytes": 128 * 1024,
                    "tail_lines": 2000,
                },
            },
            "adaptive_policy": {
                "enabled": True,
                "aggressiveness": "normal",  # low|normal|high
                "require_confirmation_for_risky": True,
            },
            "incremental_policy": {
                "enabled": True,
                "baseline_frequency_runs": 5,
                "compact_delta": True,
            },
            "network_policy": {
                "external_traffic_allowed": False,
                "local_scan_allowed": True,
                "web_probe_allowed": False,
            },
            "sandbox_policy": {
                "enabled": False,
                "max_time_sec": 30,
            },
        },
        "limits": {
            "collector_timeout_sec": 30,
            "max_concurrency": 2,
            "max_snapshot_bytes_soft": 500 * 1024 * 1024,
            "max_artifact_preview_bytes": 256 * 1024,
            "pass_time_budget_ms": {
                "pass1": 60_000,
                "pass2": 120_000,
                "pass3": 180_000,
            },
        },
        "server": {
            "enabled": False,
            "bind": "0.0.0.0",
            "port": 0,  # 0 = auto
            "token": gen_token(),
            "safe_view_default": True,
        },
        "dependencies": {
            "auto_install_enabled": True,
            "cleanup_after_run_enabled": False,
            "offline_mode_forced": False,
            "registry_path": "deps/registry.json",
        },
        "collectors": {
            "enable_defaults": True,
            "explicit_enable": [],
            "explicit_disable": [],
        },
        "apps": {
            "allowlist_enabled": True,
            "require_confirmation_for_risky": True,
        },
        "allowlist": {
            # Allowlist is strict: only known/supported apps are expected.
            # This list is also referenced by the allowlist_apps collector.
            "apps": [
                "nfqws2-keenetic",
                "nfqws-keenetic-web",
                "hydraroute",
                "magitrickle",
                "awg-manager",
            ],
        },
        "exports": {
            "default_redaction_level": "strict",
        },
    }


class ConfigError(RuntimeError):
    pass


@dataclasses.dataclass
class ConfigManager:
    base_path: Path

    @property
    def config_path(self) -> Path:
        return self.base_path / "config" / "rdct.json"

    def load_or_create(self) -> Dict[str, Any]:
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        if not self.config_path.exists():
            cfg = default_config(self.base_path)
            self.save(cfg)
            return cfg

        try:
            cfg = json.loads(self.config_path.read_text(encoding="utf-8"))
        except Exception as e:
            raise ConfigError(f"Failed to read config: {self.config_path} ({e})")
        cfg = self._migrate(cfg)
        # Ensure token exists
        if not cfg.get("server", {}).get("token"):
            cfg.setdefault("server", {})["token"] = gen_token()
            self.save(cfg)
        return cfg

    def save(self, cfg: Dict[str, Any]) -> None:
        self.config_path.write_text(stable_json_dumps(cfg) + "\n", encoding="utf-8")

    def _migrate(self, cfg: Dict[str, Any]) -> Dict[str, Any]:
        # Placeholder for future migrations. For now, ensure required keys exist.
        if "config_version" not in cfg:
            cfg["config_version"] = DEFAULT_CONFIG_VERSION
        # Merge missing defaults non-destructively
        defaults = default_config(self.base_path)
        merged = _deep_merge(defaults, cfg)
        return merged


def _deep_merge(base: Dict[str, Any], overlay: Dict[str, Any]) -> Dict[str, Any]:
    out = dict(base)
    for k, v in overlay.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out
