from __future__ import annotations

import dataclasses
import os
import resource
import shlex
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from ..utils import CommandResult, redact_text, sha256_file, utc_now_iso, write_json
from ..constants import ERRORS_VERSION, RESULT_VERSION


@dataclasses.dataclass
class CollectorMeta:
    collector_id: str
    name: str
    version: str
    category: str
    requires_root: bool = False
    default_enabled: bool = True


@dataclasses.dataclass
class CollectorContext:
    run_id: str
    snapshot_root: Path
    logs_root: Path
    research_mode: str
    performance_mode: str
    redaction_enabled: bool
    redaction_level: str
    limits: Dict[str, Any]
    tool_logger: Any  # logging.Logger
    signals: Dict[str, Any]
    stop_requested_flag: Any  # callable returning bool

    def should_stop(self) -> bool:
        try:
            return bool(self.stop_requested_flag())
        except Exception:
            return False


class CollectorError(RuntimeError):
    pass


class BaseCollector:
    META: CollectorMeta

    def __init__(self) -> None:
        if not hasattr(self, "META"):
            raise TypeError("Collector must define META")

    def enabled_by_default(self) -> bool:
        return bool(self.META.default_enabled)

    def out_dir(self, ctx: CollectorContext) -> Path:
        # A collector writes artifacts into its category directory by default.
        # NOTE: category folders are part of the public snapshot structure.
        return ctx.snapshot_root / self.META.category

    def logs_dir(self, ctx: CollectorContext) -> Path:
        return ctx.snapshot_root / "logs" / "collectors" / self.META.collector_id

    def _artifact_id(self, rel_path: str) -> str:
        # Stable within a snapshot.
        return f"{self.META.collector_id}:{rel_path}"

    def _register_artifact(
        self,
        ctx: CollectorContext,
        *,
        path: Path,
        type_: str,
        sensitive: bool,
        redacted: bool,
        description: str = "",
        tags: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        rel = str(path.relative_to(ctx.snapshot_root))
        sha = sha256_file(path)
        return {
            "artifact_id": self._artifact_id(rel),
            "path": rel,
            "type": type_,
            "size_bytes": int(path.stat().st_size),
            "sha256": sha,
            "sensitive": bool(sensitive),
            "redacted": bool(redacted),
            "description": description or None,
            "tags": tags or [],
        }

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        """
        Return a dict matching (at least) the result.json schema fields:
        - findings, artifacts, normalized_data, next_suggestions, stats
        """
        raise NotImplementedError

    # ---------- helpers ----------

    def _write_text(self, ctx: CollectorContext, rel_path: str, text: str, sensitive: bool = False) -> Path:
        p = ctx.snapshot_root / rel_path
        p.parent.mkdir(parents=True, exist_ok=True)
        if ctx.redaction_enabled and sensitive:
            text = redact_text(text, ctx.redaction_level)
        p.write_text(text, encoding="utf-8", errors="ignore")
        return p

    def _run_cmd(
        self,
        ctx: CollectorContext,
        cmd: List[str],
        timeout_sec: Optional[int] = None,
        sensitive_output: bool = False,
        cwd: Optional[Path] = None,
        env: Optional[Dict[str, str]] = None,
    ) -> CommandResult:
        logs_dir = self.logs_dir(ctx)
        logs_dir.mkdir(parents=True, exist_ok=True)
        stdout_path = logs_dir / "stdout.log"
        stderr_path = logs_dir / "stderr.log"

        # Respect USB-only: redirect temp to snapshot run dir where possible.
        run_tmp = str((ctx.snapshot_root / "logs" / "tmp").resolve())
        os.makedirs(run_tmp, exist_ok=True)

        merged_env = dict(os.environ)
        merged_env["TMPDIR"] = run_tmp
        merged_env["TEMP"] = run_tmp
        merged_env["TMP"] = run_tmp
        merged_env["PYTHONDONTWRITEBYTECODE"] = "1"
        if env:
            merged_env.update(env)

        timeout = timeout_sec or int(ctx.limits.get("collector_timeout_sec", 30))

        start = time.time()
        # Resource limits: best-effort and conservative.
        def preexec():
            try:
                # Avoid fork bombs; keep it low.
                resource.setrlimit(resource.RLIMIT_NPROC, (64, 64))
            except Exception:
                pass
            try:
                # Cap core dump size.
                resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
            except Exception:
                pass

        with stdout_path.open("w", encoding="utf-8") as out, stderr_path.open("w", encoding="utf-8") as err:
            try:
                p = subprocess.run(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=timeout,
                    cwd=str(cwd) if cwd else None,
                    env=merged_env,
                    text=True,
                    errors="ignore",
                    preexec_fn=preexec if hasattr(os, "geteuid") else None,
                )
                stdout = p.stdout or ""
                stderr = p.stderr or ""
                if ctx.redaction_enabled and sensitive_output:
                    stdout = redact_text(stdout, ctx.redaction_level)
                    stderr = redact_text(stderr, ctx.redaction_level)
                out.write(stdout)
                err.write(stderr)
                code = int(p.returncode)
            except subprocess.TimeoutExpired as e:
                out.write((e.stdout or "") if isinstance(e.stdout, str) else "")
                err.write((e.stderr or "") if isinstance(e.stderr, str) else "")
                code = 124
            except FileNotFoundError:
                err.write("command_not_found\n")
                code = 127

        dur_ms = int((time.time() - start) * 1000)
        return CommandResult(command=" ".join(shlex.quote(x) for x in cmd), exit_code=code,
                             stdout_path=str(stdout_path), stderr_path=str(stderr_path), duration_ms=dur_ms)

    def _result_template(self, ctx: CollectorContext, status: str) -> Dict[str, Any]:
        return {
            "result_version": RESULT_VERSION,
            "collector": {
                "name": self.META.name,
                "version": self.META.version,
                "collector_id": self.META.collector_id,
            },
            "run": {
                "run_id": ctx.run_id,
                "start_time": utc_now_iso(),
                "end_time": None,
                "duration_ms": None,
                "status": status,
            },
            "scope": {
                "research_mode": ctx.research_mode,
                "performance_mode": ctx.performance_mode,
                "requires_root": bool(self.META.requires_root),
                "effective_root": bool(os.geteuid() == 0) if hasattr(os, "geteuid") else False,
                "redaction_enabled": bool(ctx.redaction_enabled),
                "redaction_level": str(ctx.redaction_level),
            },
            "stats": {
                "items_collected": 0,
                "files_written": 0,
                "bytes_written": 0,
            },
            "artifacts": [],
            "findings": [],
            "next_suggestions": [],
        }

    def _finalize_result(self, ctx: CollectorContext, result: Dict[str, Any], started_at: float) -> Dict[str, Any]:
        result["run"]["end_time"] = utc_now_iso()
        result["run"]["duration_ms"] = int((time.time() - started_at) * 1000)
        return result

    def write_result_json(self, ctx: CollectorContext, result: Dict[str, Any]) -> Path:
        p = self.logs_dir(ctx) / "result.json"
        write_json(p, result)
        return p

    def write_errors_json(self, ctx: CollectorContext, errors: List[Dict[str, Any]], warnings: List[Dict[str, Any]]) -> Optional[Path]:
        if not errors and not warnings:
            return None
        p = self.logs_dir(ctx) / "errors.json"
        payload = {
            "errors_version": ERRORS_VERSION,
            "collector_id": self.META.collector_id,
            "run_id": ctx.run_id,
            "generated_at": utc_now_iso(),
            "errors": errors,
            "warnings": warnings,
            "debug_refs": [],
        }
        write_json(p, payload)
        return p
