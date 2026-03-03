from __future__ import annotations

import json
import os
import resource
import shutil
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from .collectors import collectors_by_id
from .collectors.base import BaseCollector, CollectorContext
from .constants import API_VERSION, MANIFEST_VERSION, SUPPORTED_ARCH, SUPPORTED_LANGUAGES, TOOL_NAME, TOOL_VERSION, UI_VERSION
from .incremental.index import IndexManager
from .logging_setup import setup_logging
from .policy.engine import PolicyEngine
from .storage import StorageLayout, preflight_usb_only, usb_health_summary
from .utils import stable_json_dumps, utc_now_iso, write_json


@dataclass
class RunResult:
    run_id: str
    status: str
    snapshot_path: Path
    archive_path: Optional[Path]
    manifest_path: Path


class RDCTCore:
    """Main orchestration engine.

    Key guarantees (per TZ):
      - USB-only storage for every write
      - deterministic snapshot structure
      - adaptive multi-pass execution
      - manifest + checksums
    """

    def __init__(self, layout: StorageLayout, config: Dict[str, Any]) -> None:
        self.layout = layout
        self.config = config

        self._stop_flag = threading.Event()
        self._pause_flag = threading.Event()

        # Minimal progress state for WebUI/API.
        self._progress_lock = threading.Lock()
        self._progress: Dict[str, Any] = {
            "running": False,
            "run_id": None,
            "phase": None,
            "current_collector": None,
            "started_at": None,
            "last_update": None,
        }

        # Tool logger goes into logs_dir/tool/rdct.log (USB-only).
        self.tool_log_path = self.layout.logs_dir / "tool" / "rdct.log"
        self.logger = setup_logging(self.tool_log_path, level="INFO")

        # Incremental/diff index manager
        self.index_mgr = IndexManager(self.layout.cache_dir / "incremental")

        # Policy engine
        rules_path = Path(__file__).parent / "policy" / "rules.json"
        self.policy_engine = PolicyEngine(rules_path)

    # ---------- control ----------

    def request_stop(self) -> None:
        self._stop_flag.set()

    def request_pause(self) -> None:
        self._pause_flag.set()

    def request_resume(self) -> None:
        self._pause_flag.clear()

    def stop_requested(self) -> bool:
        return self._stop_flag.is_set()

    def paused(self) -> bool:
        return self._pause_flag.is_set()

    def progress(self) -> Dict[str, Any]:
        with self._progress_lock:
            return dict(self._progress)

    def _set_progress(self, **kw: Any) -> None:
        with self._progress_lock:
            self._progress.update(kw)
            self._progress["last_update"] = utc_now_iso()

    def _wait_if_paused(self) -> None:
        while self.paused() and not self.stop_requested():
            time.sleep(0.2)

    # ---------- public API ----------

    def preflight(self) -> StorageLayout:
        self.logger.info("Preflight: enforcing USB-only storage layout.")
        layout = preflight_usb_only(self.layout)
        self.logger.info(usb_health_summary(layout))
        return layout

    def run(
        self,
        *,
        initiator: str = "cli",
        requested_mode: Optional[str] = None,
        requested_perf: Optional[str] = None,
        force_baseline: bool = False,
    ) -> RunResult:
        """Execute a diagnostic run and produce a snapshot in reports_dir."""

        self.preflight()
        self._stop_flag.clear()
        self._pause_flag.clear()

        run_started_at = utc_now_iso()
        run_started_ts = time.time()

        # Determine effective modes
        modes = self.config.get("modes", {}) or {}
        research_mode = (requested_mode or modes.get("research_mode") or "light").lower()
        # Back-compat / aliases
        if research_mode == "deep":
            research_mode = "full"
        if research_mode not in {"light", "medium", "full", "extreme"}:
            raise ValueError("research_mode must be one of light/medium/full/extreme (deep is alias for full)")
        performance_mode = (requested_perf or modes.get("performance_mode") or "auto").lower()

        red = modes.get("redaction", {}) or {}
        redaction_enabled = bool(red.get("enabled", True))
        redaction_level = str(red.get("level", "strict"))

        # Prepare run dirs (on USB)
        run_id = self._make_run_id()
        staging_dir = self.layout.run_dir / f"run_{run_id}"
        snapshot_root = staging_dir / "snapshot"
        snapshot_root.mkdir(parents=True, exist_ok=True)
        self._init_snapshot_structure(snapshot_root)

        # Run-specific tool log inside snapshot
        run_log_handler = None
        try:
            import logging

            run_log_path = snapshot_root / "logs" / "tool" / "rdct.log"
            run_log_path.parent.mkdir(parents=True, exist_ok=True)
            run_log_handler = logging.FileHandler(run_log_path, encoding="utf-8")
            run_log_handler.setLevel(self.logger.level)
            # Match formatter from setup_logging
            fmt = logging.Formatter(fmt="%(asctime)s %(levelname)s %(name)s: %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
            run_log_handler.setFormatter(fmt)
            self.logger.addHandler(run_log_handler)
        except Exception:
            run_log_handler = None

        self._set_progress(running=True, run_id=run_id, phase="pass1", current_collector=None, started_at=run_started_at)

        # Signals for policy / collectors
        signals: Dict[str, Any] = {}
        signals["config.modes.network_policy"] = modes.get("network_policy", {}) or {}
        signals["config.modes.mirror_policy"] = modes.get("mirror_policy", {}) or {}
        signals["config.modes.adaptive_policy"] = modes.get("adaptive_policy", {}) or {}
        signals["config.modes.incremental_policy"] = modes.get("incremental_policy", {}) or {}

        allowlist = self.config.get("allowlist", {}) or {}
        signals["config.allowlist.apps"] = allowlist.get("apps") or []

        signals["storage.install_dir"] = str(self.layout.install_dir)
        signals["storage.deps_dir"] = str(self.layout.deps_dir)
        signals["storage.cache_dir"] = str(self.layout.cache_dir)
        signals["storage.run_dir"] = str(self.layout.run_dir)
        signals["storage.reports_dir"] = str(self.layout.reports_dir)
        signals["storage.logs_dir"] = str(self.layout.logs_dir)

        # Core-level quick metrics
        self._populate_quick_signals(signals)

        ctx = CollectorContext(
            run_id=run_id,
            snapshot_root=snapshot_root,
            logs_root=self.layout.logs_dir,
            research_mode=research_mode,
            performance_mode=performance_mode,
            redaction_enabled=redaction_enabled,
            redaction_level=redaction_level,
            limits=self.config.get("limits", {}) or {},
            tool_logger=self.logger,
            signals=signals,
            stop_requested_flag=self.stop_requested,
        )

        # Record run context early
        self._write_run_context(ctx, initiator=initiator)

        # Incremental: load index, decide baseline/delta
        inc_policy = modes.get("incremental_policy", {}) or {}
        inc_enabled = bool(inc_policy.get("enabled", True))
        idx = self.index_mgr.load()
        baseline_run_id, baseline_norm = self.index_mgr.get_baseline(idx)
        runs_since = self.index_mgr.runs_since_baseline(idx)
        signals["incremental.enabled"] = inc_enabled
        signals["incremental.baseline_run_id"] = baseline_run_id
        signals["incremental.runs_since_baseline"] = runs_since

        run_mode = "baseline"
        if inc_enabled and baseline_run_id and not force_baseline:
            run_mode = "delta"
        if force_baseline or not baseline_run_id:
            run_mode = "baseline"

        self.logger.info(
            f"Run starting: run_id={run_id} mode={run_mode} research={research_mode} perf={performance_mode}"
        )

        # Collector registry
        all_collectors = collectors_by_id()
        enabled = self._select_enabled_collectors(all_collectors)

        # Pass tracking
        passes: List[Dict[str, Any]] = []

        results: Dict[str, Dict[str, Any]] = {}
        all_findings: List[Dict[str, Any]] = []
        normalized: Dict[str, Any] = {}
        adaptive_executed_actions: List[Dict[str, Any]] = []

        def run_pass(pass_id: str, description: str, collector_ids: List[str], triggered_by: Optional[List[str]] = None) -> None:
            nonlocal results, all_findings, normalized

            started_at = utc_now_iso()
            self._set_progress(phase=pass_id, current_collector=None)
            pinfo = {
                "pass_id": pass_id,
                "description": description,
                "started_at": started_at,
                "ended_at": None,
                "status": "running",
                "triggered_by": triggered_by or [],
                "collectors_run": [],
            }
            passes.append(pinfo)

            for cid in collector_ids:
                if self.stop_requested():
                    break
                self._wait_if_paused()
                c = enabled.get(cid)
                if not c:
                    continue
                self._set_progress(current_collector=cid)
                r = self._run_one_collector(c, ctx)
                results[cid] = r
                pinfo["collectors_run"].append(cid)
                all_findings.extend(r.get("findings", []) or [])
                nd = r.get("normalized_data") or {}
                if isinstance(nd, dict):
                    normalized.update(nd)

            pinfo["ended_at"] = utc_now_iso()
            pinfo["status"] = "aborted" if self.stop_requested() else "success"

        # --- Pass 1: mandatory cheap baseline data
        pass1_ids = [
            "mvp-01-device-info",
            "mvp-02-environment",
            "mvp-03-storage",
            "mvp-04-proc-snapshot",
            "mvp-05-dmesg",
            "mvp-06-network-basics",
            "mvp-07-routes-rules",
            "mvp-08-sockets-ports",
            "mvp-09-keenetic-config",
            "mvp-10-ndm-events-hooks",
            "mvp-11-entware-opkg",
            "mvp-12-entware-services",
        ]
        run_pass("pass1", "Baseline inventory (cheap collectors)", pass1_ids, triggered_by=["initial"])

        # --- Adaptive policy evaluation after pass1
        plan: Optional[Dict[str, Any]] = None
        plan_rel: Optional[str] = None
        adaptive_policy = modes.get("adaptive_policy", {}) or {}
        if bool(adaptive_policy.get("enabled", True)):
            signals["core.all_findings"] = all_findings
            signals["incremental"] = {
                "enabled": inc_enabled,
                "baseline_run_id": baseline_run_id,
                "baseline_normalized": baseline_norm,
                "current_normalized": normalized,
            }
            if baseline_norm and normalized and isinstance(baseline_norm.get("listening_ports"), list) and isinstance(
                normalized.get("listening_ports"), list
            ):
                opened = set(normalized["listening_ports"]) - set(baseline_norm["listening_ports"])
                signals["diff.new_listening_ports_count"] = len(opened)

            require_conf = bool(adaptive_policy.get("require_confirmation_for_risky", True))
            plan = self.policy_engine.evaluate(signals, research_mode=research_mode, require_confirmation_for_risky=require_conf)
            plan_path = snapshot_root / "adaptive" / "plan.json"
            plan_path.parent.mkdir(parents=True, exist_ok=True)
            write_json(plan_path, plan)
            plan_rel = str(plan_path.relative_to(snapshot_root))

            # Apply safe auto overrides/actions
            executed = self._apply_policy_auto(plan, enabled, ctx)
            adaptive_executed_actions.extend(executed)

        # --- Pass 2: targeted diagnostics (medium/full/extreme)
        pass2_default: List[str] = []
        if research_mode in {"medium", "full", "extreme"}:
            pass2_default = [
                "ext-01-firewall",
                "ext-02-conntrack",
                "ext-03-dns",
                "ext-04-dhcp",
                "ext-05-wifi",
                "ext-06-vpn",
                "ext-10-app-inventory",
                "ext-11-app-debug-bundles",
                "ext-12-allowlist-apps",
                "ext-13-timeline",
                "ext-14-performance-profile",
                "mvp-13-web-discovery",
                "ext-16-js-api-extractor",
            ]
            run_pass("pass2", "Targeted diagnostics (network/apps/web)", pass2_default, triggered_by=self._pass_triggers(plan, kind="pass2"))

        # --- Pass 3: deep / heavy (full/extreme)
        pass3_default: List[str] = []
        if research_mode in {"full", "extreme"}:
            pass3_default = [
                "ext-07-file-security",
                "ext-08-recent-changes",
                "ext-09-large-files",
                "ext-15-sandbox-tests",
                "mvp-15-mirror",
            ]
            # Any enabled collectors not explicitly scheduled will run in pass3 (stable order by id).
            scheduled = set(pass1_ids + pass2_default + pass3_default + ["mvp-18-diff", "mvp-14-sensitive-scan", "mvp-16-summary"])
            remaining = sorted([cid for cid in enabled.keys() if cid not in scheduled and cid != "mvp-17-checksums"])
            pass3_default.extend(remaining)
            run_pass("pass3", "Deep diagnostics (filesystem / sandbox / mirror)", pass3_default, triggered_by=self._pass_triggers(plan, kind="pass3"))

        # --- Finalization collectors
        # Diff first (so its findings are available for summary)
        signals["incremental"] = {
            "enabled": inc_enabled,
            "baseline_run_id": baseline_run_id,
            "baseline_normalized": baseline_norm,
            "current_normalized": normalized,
        }
        run_pass(
            "finalize",
            "Finalize (diff/sensitive/summary)",
            [
                "mvp-18-diff",
                "mvp-14-sensitive-scan",
                "mvp-16-summary",
            ],
        )

        # Update incremental index (cache) and export a copy into snapshot
        if inc_enabled:
            agg_norm = self._normalize_for_index(normalized)
            snapshot_rel = f"{run_id}/snapshot"
            idx2 = self.index_mgr.load()
            idx2 = self.index_mgr.update_run(idx2, run_id=run_id, mode=run_mode, normalized=agg_norm, snapshot_relpath=snapshot_rel)
            self.index_mgr.save(idx2)

            # Export for transparency
            export_dir = snapshot_root / "incremental"
            export_dir.mkdir(parents=True, exist_ok=True)
            write_json(export_dir / "index.json", idx2)
            write_json(export_dir / f"{run_id}.normalized.json", agg_norm)
            if baseline_run_id and baseline_norm:
                write_json(export_dir / f"{baseline_run_id}.baseline.normalized.json", baseline_norm)

        # Prepare a pseudo-collector log entry for checksums (but write checksums file after manifest).
        self._prepare_checksums_logs(ctx)
        # Include the pseudo result in the results map so it appears in manifest.collectors.
        results["mvp-17-checksums"] = self._load_checksums_result(ctx) or {
            "run": {"status": "success"},
            "findings": [],
            "artifacts": [],
        }

        # Build manifest BEFORE moving snapshot to reports dir.
        status = "success" if not self.stop_requested() else "aborted"
        run_ended_at = utc_now_iso()
        duration_ms = int((time.time() - run_started_ts) * 1000)

        # Predict checksums coverage count: all current files + manifest (but excluding checksums file).
        covered_files_count = self._predict_covered_files(snapshot_root)

        manifest = self._build_manifest(
            ctx,
            status=status,
            run_mode=run_mode,
            initiator=initiator,
            run_started_at=run_started_at,
            run_ended_at=run_ended_at,
            duration_ms=duration_ms,
            results=results,
            findings=all_findings,
            passes=passes,
            plan=plan,
            plan_rel=plan_rel,
            adaptive_executed_actions=adaptive_executed_actions,
            covered_files_count=covered_files_count,
        )
        manifest_path = snapshot_root / "manifest.json"
        write_json(manifest_path, manifest)

        # Stop writing run-scoped tool logs into snapshot before generating checksums.
        if run_log_handler is not None:
            try:
                self.logger.removeHandler(run_log_handler)
                run_log_handler.close()
            except Exception:
                pass
            run_log_handler = None

        # Compute and write checksums as the final snapshot write.
        self._write_checksums_file(snapshot_root)

        # After manifest is written, checksums collector (if enabled) will include it.

        # Move to reports_dir and create archive
        dest_run_dir = self.layout.reports_dir / run_id
        dest_snapshot = dest_run_dir / "snapshot"
        dest_run_dir.mkdir(parents=True, exist_ok=True)
        if dest_snapshot.exists():
            shutil.rmtree(dest_snapshot)
        shutil.move(str(snapshot_root), str(dest_snapshot))

        # Cleanup staging
        shutil.rmtree(staging_dir, ignore_errors=True)

        archive_path = self._make_archive(dest_run_dir, dest_snapshot)

        # Record free space after
        try:
            st = os.statvfs(str(self.layout.base_path))
            self.layout.free_space_after_bytes = st.f_bavail * st.f_frsize
        except Exception:
            pass

        self._set_progress(running=False, current_collector=None, phase=None)
        self.logger.info(f"Run finished: {run_id} status={status} report_dir={dest_run_dir}")

        return RunResult(
            run_id=run_id,
            status=status,
            snapshot_path=dest_snapshot,
            archive_path=archive_path,
            manifest_path=dest_snapshot / "manifest.json",
        )

    # ---------- internal helpers ----------

    def _init_snapshot_structure(self, snapshot_root: Path) -> None:
        # Create required top-level dirs (even if empty)
        for d in [
            "meta",
            "device",
            "environment",
            "system",
            "network",
            "security",
            "apps",
            "web",
            "mirror",
            "incremental",
            "diff",
            "reports",
            "adaptive",
            "logs/collectors",
            "logs/tool",
        ]:
            (snapshot_root / d).mkdir(parents=True, exist_ok=True)

    def _make_run_id(self) -> str:
        t = time.strftime("%Y%m%d_%H%M%SZ", time.gmtime())
        rand = os.urandom(3).hex()
        return f"{t}_{rand}"

    def _predict_covered_files(self, snapshot_root: Path) -> int:
        # Covered files are all files that will exist after manifest is written,
        # excluding the checksums file itself.
        count = 0
        for p in snapshot_root.rglob("*"):
            if p.is_file() and p.name != "checksums.sha256":
                count += 1
        # add manifest (not present in count yet)
        return count + 1

    def _populate_quick_signals(self, signals: Dict[str, Any]) -> None:
        try:
            la = Path("/proc/loadavg").read_text(encoding="utf-8", errors="ignore").split()
            signals["system.loadavg_1m"] = float(la[0])
            signals["system.loadavg_5m"] = float(la[1])
            signals["system.loadavg_15m"] = float(la[2])
        except Exception:
            pass
        try:
            mem = Path("/proc/meminfo").read_text(encoding="utf-8", errors="ignore").splitlines()
            for ln in mem:
                if ln.startswith("MemAvailable:"):
                    kb = int(ln.split()[1])
                    signals["system.mem_available_bytes"] = kb * 1024
        except Exception:
            pass
        if self.layout.free_space_before_bytes is not None:
            signals["system.usb_free_bytes"] = int(self.layout.free_space_before_bytes)

        signals["env.opt_on_usb"] = self._is_opt_on_usb()

    def _is_opt_on_usb(self) -> bool:
        try:
            from .storage import find_mount_for_path, is_external_device, is_virtual_fs, read_proc_mounts

            mounts = read_proc_mounts()
            mi = find_mount_for_path(Path("/opt"), mounts)
            if not mi:
                return False
            if is_virtual_fs(mi):
                return False
            return is_external_device(mi)
        except Exception:
            return False

    def _select_enabled_collectors(self, all_collectors: Dict[str, BaseCollector]) -> Dict[str, BaseCollector]:
        cfg = self.config.get("collectors", {}) or {}
        enable_defaults = bool(cfg.get("enable_defaults", True))
        explicit_enable = set(cfg.get("explicit_enable") or [])
        explicit_disable = set(cfg.get("explicit_disable") or [])
        enabled: Dict[str, BaseCollector] = {}
        for cid, c in all_collectors.items():
            if cid in explicit_disable:
                continue
            if cid in explicit_enable:
                enabled[cid] = c
                continue
            if enable_defaults and c.enabled_by_default():
                enabled[cid] = c
        return enabled

    def _run_one_collector(self, c: BaseCollector, ctx: CollectorContext) -> Dict[str, Any]:
        if ctx.should_stop():
            return {"run": {"status": "skipped"}, "findings": [], "artifacts": [], "normalized_data": {}}

        # Root gate
        if getattr(c.META, "requires_root", False) and hasattr(os, "geteuid") and os.geteuid() != 0:
            r = c._result_template(ctx, status="skipped")
            r["run"]["status"] = "skipped"
            r.setdefault("findings", []).append(
                {
                    "severity": "info",
                    "code": "requires_root",
                    "title": "Collector requires root",
                    "details": f"Collector {c.META.collector_id} skipped because not running as root.",
                    "refs": [],
                }
            )
            c.write_result_json(ctx, r)
            c.write_errors_json(ctx, errors=[], warnings=[])
            return r

        # Measure (best-effort) per-collector resource usage.
        ru0 = resource.getrusage(resource.RUSAGE_SELF)
        io0 = self._read_proc_io()

        self.logger.info(f"Collector start: {c.META.collector_id}")
        try:
            r = c.run(ctx)
            # Normalize status
            st = (r.get("run", {}) or {}).get("status")
            if st == "error":
                r["run"]["status"] = "failed"
        except Exception as e:
            self.logger.exception(f"Collector failed: {c.META.collector_id}: {e}")
            r = c._result_template(ctx, status="failed")
            r["run"]["status"] = "failed"
            r.setdefault("findings", []).append(
                {
                    "severity": "high",
                    "code": "collector_exception",
                    "title": "Collector exception",
                    "details": str(e),
                    "refs": [],
                }
            )
            c.write_result_json(ctx, r)
            c.write_errors_json(ctx, errors=[{"time": utc_now_iso(), "level": "error", "code": "collector_exception", "message": str(e)}], warnings=[])

        ru1 = resource.getrusage(resource.RUSAGE_SELF)
        io1 = self._read_proc_io()
        r.setdefault("run", {}).setdefault("resource_usage", {})
        r["run"]["resource_usage"] = {
            "cpu_time_ms": int(((ru1.ru_utime + ru1.ru_stime) - (ru0.ru_utime + ru0.ru_stime)) * 1000),
            "max_rss_kb": int(getattr(ru1, "ru_maxrss", 0)),
            "io_bytes_read": max(0, io1.get("read_bytes", 0) - io0.get("read_bytes", 0)),
            "io_bytes_written": max(0, io1.get("write_bytes", 0) - io0.get("write_bytes", 0)),
        }

        self.logger.info(f"Collector end: {c.META.collector_id} status={r.get('run',{}).get('status')}")
        return r

    def _read_proc_io(self) -> Dict[str, int]:
        out: Dict[str, int] = {"read_bytes": 0, "write_bytes": 0}
        try:
            for ln in Path("/proc/self/io").read_text(encoding="utf-8", errors="ignore").splitlines():
                if ln.startswith("read_bytes:"):
                    out["read_bytes"] = int(ln.split()[1])
                if ln.startswith("write_bytes:"):
                    out["write_bytes"] = int(ln.split()[1])
        except Exception:
            pass
        return out

    def _apply_policy_auto(self, plan: Dict[str, Any], enabled: Dict[str, BaseCollector], ctx: CollectorContext) -> List[Dict[str, Any]]:
        executed: List[Dict[str, Any]] = []

        overrides = plan.get("config_overrides", {}) or {}
        disabled = overrides.get("collectors.disabled") or []
        for cid in disabled:
            if cid in enabled:
                enabled.pop(cid, None)
                executed.append({"type": "disable_collector", "collector_id": cid, "decision": "auto"})

        perf = overrides.get("performance_mode")
        if perf:
            ctx.performance_mode = str(perf)
            executed.append({"type": "set", "key": "performance_mode", "value": str(perf), "decision": "auto"})

        if "limits.max_concurrency" in overrides:
            try:
                ctx.limits["max_concurrency"] = int(overrides["limits.max_concurrency"])
                executed.append(
                    {
                        "type": "set",
                        "key": "limits.max_concurrency",
                        "value": int(overrides["limits.max_concurrency"]),
                        "decision": "auto",
                    }
                )
            except Exception:
                pass

        # Run collector actions (auto only)
        for a in plan.get("auto_actions") or []:
            if a.startswith("run_collector:"):
                cid = a.split(":", 1)[1]
                if cid in collectors_by_id():
                    enabled[cid] = collectors_by_id()[cid]
                    executed.append({"type": "run_collector", "collector_id": cid, "decision": "auto"})

        return executed

    def _pass_triggers(self, plan: Optional[Dict[str, Any]], *, kind: str) -> List[str]:
        if not plan:
            return []
        # Best-effort: return triggered rule ids that had any actions
        out: List[str] = []
        for d in plan.get("decisions") or []:
            if d.get("decision") in {"auto", "suggested"} and (d.get("actions") or []):
                out.append(str(d.get("rule_id")))
        return out[:10]

    def _write_run_context(self, ctx: CollectorContext, initiator: str) -> None:
        meta = {
            "run_id": ctx.run_id,
            "generated_at": utc_now_iso(),
            "initiator": initiator,
            "research_mode": ctx.research_mode,
            "performance_mode": ctx.performance_mode,
            "redaction": {"enabled": ctx.redaction_enabled, "level": ctx.redaction_level},
            "storage": self.layout.as_dict(),
            "config_path": str((self.layout.base_path / "config" / "rdct.json")),
        }
        p = ctx.snapshot_root / "meta" / "run_context.json"
        p.parent.mkdir(parents=True, exist_ok=True)
        write_json(p, meta)

    def _normalize_for_index(self, normalized: Dict[str, Any]) -> Dict[str, Any]:
        out: Dict[str, Any] = {}
        for k in [
            "packages",
            "process_signatures",
            "listening_ports",
            "routes_sha256",
            "rules_sha256",
            "config_sha256",
            "http_endpoints",
            "keeneticos_version",
        ]:
            if k in normalized:
                out[k] = normalized[k]
        return out

    def _build_manifest(
        self,
        ctx: CollectorContext,
        *,
        status: str,
        run_mode: str,
        initiator: str,
        run_started_at: str,
        run_ended_at: str,
        duration_ms: int,
        results: Dict[str, Dict[str, Any]],
        findings: List[Dict[str, Any]],
        passes: List[Dict[str, Any]],
        plan: Optional[Dict[str, Any]],
        plan_rel: Optional[str],
        adaptive_executed_actions: List[Dict[str, Any]],
        covered_files_count: int,
    ) -> Dict[str, Any]:
        # Read key device/environment info if present
        device_info = self._safe_read_json(ctx.snapshot_root / "device" / "device_info.json") or {}
        env_tools = self._safe_read_json(ctx.snapshot_root / "environment" / "tools_inventory.json") or {}
        keeneticos = self._safe_read_json(ctx.snapshot_root / "environment" / "keeneticos.json") or {}
        entware = self._safe_read_json(ctx.snapshot_root / "environment" / "entware.json") or {}

        # Sensitive report counters (best-effort)
        sens = self._safe_read_json(ctx.snapshot_root / "security" / "sensitive_findings.json") or {}
        sens_items = sens.get("items") if isinstance(sens, dict) else None
        items_count = len(sens_items) if isinstance(sens_items, list) else None
        high_risk = None
        if isinstance(sens_items, list):
            high_risk = sum(1 for x in sens_items if isinstance(x, dict) and x.get("severity") in {"high", "critical"})

        diff_report_path = None
        diff_res = results.get("mvp-18-diff") or {}
        for a in diff_res.get("artifacts") or []:
            if isinstance(a, dict) and a.get("path") == "diff/diff_report.json":
                diff_report_path = a.get("path")
                break

        # Collector entries
        collectors_manifest: List[Dict[str, Any]] = []
        artifacts_manifest: List[Dict[str, Any]] = []

        for cid, r in results.items():
            meta = collectors_by_id().get(cid)
            # meta may be absent if collector removed; fallback minimal.
            if cid == "mvp-17-checksums":
                name = "ChecksumsCollector"
                ver = "1.0"
                cat = "checksums"
                req_root = False
            else:
                name = getattr(meta.META, "name", cid) if meta else cid
                ver = getattr(meta.META, "version", "unknown") if meta else "unknown"
                cat = getattr(meta.META, "category", "unknown") if meta else "unknown"
                req_root = bool(getattr(meta.META, "requires_root", False)) if meta else False

            run = r.get("run", {}) or {}
            collectors_manifest.append(
                {
                    "collector_id": cid,
                    "name": name,
                    "version": ver,
                    "category": cat,
                    "requires_root": req_root,
                    "enabled": True,
                    "start_time": run.get("start_time"),
                    "end_time": run.get("end_time"),
                    "duration_ms": run.get("duration_ms"),
                    "status": run.get("status"),
                    "result_path": f"logs/collectors/{cid}/result.json",
                    "errors_path": f"logs/collectors/{cid}/errors.json",
                    "artifacts_refs": [a.get("artifact_id") for a in (r.get("artifacts") or []) if a.get("artifact_id")],
                    "resource_usage": run.get("resource_usage"),
                    "notes": [],
                }
            )

            for a in r.get("artifacts") or []:
                if not isinstance(a, dict):
                    continue
                # Convert collector artifact to manifest artifact schema
                artifacts_manifest.append(
                    {
                        "artifact_id": a.get("artifact_id") or f"{cid}:{a.get('path')}",
                        "path": a.get("path"),
                        "type": a.get("type"),
                        "producer": cid,
                        "size_bytes": a.get("size_bytes"),
                        "sha256": a.get("sha256"),
                        "sensitive": bool(a.get("sensitive", False)),
                        "redacted": bool(a.get("redacted", False)),
                        "description": a.get("description"),
                        "tags": a.get("tags") or [],
                    }
                )

        # Count errors/warnings from errors.json files if present
        errors_count, warnings_count = self._count_errors(ctx.snapshot_root)
        critical_count = sum(1 for f in findings if (f.get("severity") == "critical"))

        inc_policy = self.config.get("modes", {}).get("incremental_policy", {}) or {}
        adaptive_policy = self.config.get("modes", {}).get("adaptive_policy", {}) or {}
        mirror_policy = self.config.get("modes", {}).get("mirror_policy", {}) or {}
        network_policy = self.config.get("modes", {}).get("network_policy", {}) or {}

        manifest: Dict[str, Any] = {
            "manifest_version": MANIFEST_VERSION,
            "tool": {
                "name": TOOL_NAME,
                "version": TOOL_VERSION,
                "api_version": API_VERSION,
                "ui_version": UI_VERSION,
                "supported_arch": SUPPORTED_ARCH,
                "supported_languages": SUPPORTED_LANGUAGES,
            },
            "run": {
                "run_id": ctx.run_id,
                "start_time": run_started_at,
                "end_time": run_ended_at,
                "duration_ms": int(duration_ms),
                "status": status,
                "initiator": initiator,
                "mode": run_mode,
                "operator_actions": [],
            },
            "device": {
                "hostname": device_info.get("hostname"),
                "vendor": device_info.get("vendor"),
                "model": device_info.get("model") or device_info.get("arch"),
                "architecture": device_info.get("arch") or device_info.get("architecture"),
                "os": {
                    "name": "KeeneticOS" if keeneticos else device_info.get("os", {}).get("name") or "unknown",
                    "version": keeneticos.get("version") if keeneticos else device_info.get("os", {}).get("version"),
                    "build": keeneticos.get("build") if keeneticos else None,
                },
                "memory": {
                    "total_bytes": device_info.get("mem_total_bytes"),
                    "available_bytes": device_info.get("mem_available_bytes"),
                },
                "storage": {
                    "usb_mountpoint": self.layout.usb_mountpoint,
                    "usb_device": self.layout.usb_device,
                },
            },
            "environment": {
                "keeneticos": keeneticos or None,
                "entware": entware or None,
                "tools_inventory": (env_tools.get("tools") if isinstance(env_tools, dict) else None),
            },
            "modes": {
                "research_mode": ctx.research_mode,
                "performance_mode": ctx.performance_mode,
                "redaction": {"enabled": ctx.redaction_enabled, "level": ctx.redaction_level},
                "mirror_policy": mirror_policy,
                "adaptive_policy": adaptive_policy,
                "incremental_policy": inc_policy,
                "network_policy": network_policy,
            },
            "storage": self.layout.as_dict(),
            "dependencies": {
                "auto_install_enabled": bool(self.config.get("dependencies", {}).get("auto_install_enabled", True)),
                "cleanup_after_run_enabled": bool(self.config.get("dependencies", {}).get("cleanup_after_run_enabled", False)),
                "offline_mode_used": bool(self.config.get("dependencies", {}).get("offline_mode_forced", False)),
                "installed_by_tool": [],
                "install_log_path": "logs/tool/deps_install.log",
                "cleanup_log_path": "logs/tool/deps_cleanup.log",
            },
            "modules": [
                {"module_id": "core", "version": TOOL_VERSION, "status": "active", "start_time": run_started_at, "end_time": run_ended_at, "notes": []},
                {"module_id": "collectors", "version": TOOL_VERSION, "status": "active", "start_time": run_started_at, "end_time": run_ended_at, "notes": []},
                {"module_id": "policy_engine", "version": "1.0.0", "status": "active" if bool(adaptive_policy.get("enabled", True)) else "disabled", "notes": []},
                {"module_id": "incremental", "version": "1.1.0", "status": "active" if bool(inc_policy.get("enabled", True)) else "disabled", "notes": []},
            ],
            "collectors": collectors_manifest,
            "artifacts": artifacts_manifest,
            "checksums": {
                "algorithm": "sha256",
                "file": "checksums.sha256",
                "covered_files_count": int(covered_files_count),
            },
            "sensitive_report": {
                "path": "security/sensitive_findings.json",
                "redaction_applied": bool(ctx.redaction_enabled),
                "items_count": items_count,
                "high_risk_items_count": high_risk,
            },
            "adaptive": {
                "enabled": bool(adaptive_policy.get("enabled", True)),
                "plan_path": plan_rel,
                "executed_actions": adaptive_executed_actions,
                "suggested_actions": (plan.get("suggested_actions") if isinstance(plan, dict) else []) if plan_rel else [],
                "skipped_count": None,
            },
            "incremental": {
                "enabled": bool(inc_policy.get("enabled", True)),
                "mode": run_mode,
                "baseline_run_id": self.index_mgr.load().get("baseline_run_id"),
                "index_path": "incremental/index.json" if bool(inc_policy.get("enabled", True)) else None,
                "normalized_path": f"incremental/{ctx.run_id}.normalized.json" if bool(inc_policy.get("enabled", True)) else None,
                "diff_report_path": diff_report_path,
            },
            "passes": passes,
            "summary": {
                "errors_count": int(errors_count),
                "warnings_count": int(warnings_count),
                "critical_count": int(critical_count),
                "top_findings_path": "reports/top_findings.json",
                "recommendations_path": "reports/recommendations.json",
                "aborted_reason": "stop_requested" if self.stop_requested() else None,
            },
            "extensions": {},
        }
        return manifest

    def _safe_read_json(self, path: Path) -> Optional[Dict[str, Any]]:
        try:
            if not path.exists():
                return None
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return None

    def _count_errors(self, snapshot_root: Path) -> Tuple[int, int]:
        e = 0
        w = 0
        base = snapshot_root / "logs" / "collectors"
        if not base.exists():
            return 0, 0
        for p in base.rglob("errors.json"):
            try:
                obj = json.loads(p.read_text(encoding="utf-8"))
                e += len(obj.get("errors") or [])
                w += len(obj.get("warnings") or [])
            except Exception:
                continue
        return e, w

    def _make_archive(self, dest_run_dir: Path, dest_snapshot: Path) -> Optional[Path]:
        # Keep implementation conservative; tarfile is available.
        try:
            import tarfile

            archive = dest_run_dir / f"{dest_run_dir.name}.tar.gz"
            with tarfile.open(archive, "w:gz") as tf:
                tf.add(str(dest_snapshot), arcname="snapshot")
            return archive
        except Exception as e:
            self.logger.warning(f"Archive creation failed: {e}")
            return None

    # ---------- checksums (final snapshot write) ----------

    def _prepare_checksums_logs(self, ctx: CollectorContext) -> None:
        """Prepare logs/collectors/mvp-17-checksums/{result,errors}.json.

        We create these files *before* manifest/checksums so they are included in checksums coverage
        and in manifest.collectors.
        """
        cid = "mvp-17-checksums"
        log_dir = ctx.snapshot_root / "logs" / "collectors" / cid
        log_dir.mkdir(parents=True, exist_ok=True)

        result_path = log_dir / "result.json"
        errors_path = log_dir / "errors.json"

        if not errors_path.exists():
            write_json(
                errors_path,
                {
                    "errors_version": "1.1.0",
                    "collector_id": cid,
                    "run_id": ctx.run_id,
                    "generated_at": utc_now_iso(),
                    "errors": [],
                    "warnings": [],
                    "debug_refs": [],
                },
            )

        if not result_path.exists():
            write_json(
                result_path,
                {
                    "result_version": "1.1.0",
                    "collector": {"name": "Checksums", "version": "1.0", "collector_id": cid},
                    "run": {
                        "run_id": ctx.run_id,
                        "status": "success",
                        "start_time": utc_now_iso(),
                        "end_time": utc_now_iso(),
                        "duration_ms": 0,
                        "limits_hit": [],
                    },
                    "scope": {
                        "research_mode": ctx.research_mode,
                        "performance_mode": ctx.performance_mode,
                        "requires_root": False,
                        "effective_root": bool(os.geteuid() == 0) if hasattr(os, "geteuid") else False,
                        "redaction_enabled": bool(ctx.redaction_enabled),
                        "redaction_level": str(ctx.redaction_level),
                    },
                    "stats": {"items_collected": 0, "files_written": 2, "bytes_written": 0},
                    "findings": [],
                    "artifacts": [],
                    "normalized_data": {},
                },
            )

    def _load_checksums_result(self, ctx: CollectorContext) -> Optional[Dict[str, Any]]:
        try:
            p = ctx.snapshot_root / "logs" / "collectors" / "mvp-17-checksums" / "result.json"
            if not p.exists():
                return None
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            return None

    def _write_checksums_file(self, snapshot_root: Path) -> None:
        """Write snapshot_root/checksums.sha256 (excluding itself).

        Must be the last write inside snapshot_root.
        """
        try:
            lines: List[str] = []
            for p in sorted(snapshot_root.rglob("*")):
                if not p.is_file():
                    continue
                if p.name == "checksums.sha256":
                    continue
                rel = str(p.relative_to(snapshot_root))
                # sha256
                import hashlib

                h = hashlib.sha256()
                with p.open("rb") as f:
                    for chunk in iter(lambda: f.read(1024 * 1024), b""):
                        h.update(chunk)
                lines.append(f"{h.hexdigest()}  {rel}")
            out = snapshot_root / "checksums.sha256"
            out.write_text("\n".join(lines) + "\n", encoding="utf-8")
        except Exception as e:
            self.logger.warning(f"Checksums generation failed: {e}")
