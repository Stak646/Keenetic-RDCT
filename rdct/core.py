from __future__ import annotations

import os
import shutil
import tarfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from .collectors import collectors_by_id, default_collectors
from .collectors.base import BaseCollector, CollectorContext
from .incremental.index import IndexManager
from .logging_setup import setup_logging
from .policy.engine import PolicyEngine
from .storage import StorageLayout, preflight_usb_only, usb_health_summary
from .utils import gen_token, stable_json_dumps, utc_now_iso, write_json


@dataclass
class RunResult:
    run_id: str
    status: str
    snapshot_path: Path
    archive_path: Optional[Path]
    manifest_path: Path


class RDCTCore:
    def __init__(self, layout: StorageLayout, config: Dict[str, Any]) -> None:
        self.layout = layout
        self.config = config
        self._stop_flag = threading.Event()

        # Tool logger goes into logs_dir/tool/rdct.log (USB-only).
        self.tool_log_path = self.layout.logs_dir / "tool" / "rdct.log"
        self.logger = setup_logging(self.tool_log_path, level="INFO")

        # Index manager for incremental/diff
        self.index_mgr = IndexManager(self.layout.cache_dir)

        # Policy engine
        rules_path = Path(__file__).parent / "policy" / "rules.json"
        self.policy_engine = PolicyEngine(rules_path)

    def request_stop(self) -> None:
        self._stop_flag.set()

    def stop_requested(self) -> bool:
        return self._stop_flag.is_set()

    # ---------- public API ----------

    def preflight(self) -> StorageLayout:
        self.logger.info("Preflight: enforcing USB-only storage layout.")
        layout = preflight_usb_only(self.layout)
        self.logger.info(usb_health_summary(layout))
        return layout

    def run(self, *, initiator: str = "cli", requested_mode: Optional[str] = None, requested_perf: Optional[str] = None,
            force_baseline: bool = False) -> RunResult:
        """
        Execute a diagnostic run and produce a snapshot in reports_dir.
        """
        self.preflight()

        # Determine effective modes
        modes = self.config.get("modes", {})
        research_mode = (requested_mode or modes.get("research_mode") or "light").lower()
        performance_mode = (requested_perf or modes.get("performance_mode") or "auto").lower()

        red = modes.get("redaction", {}) or {}
        redaction_enabled = bool(red.get("enabled", True))
        redaction_level = str(red.get("level", "strict"))

        # Prepare run dirs (on USB)
        run_id = self._make_run_id()
        staging_dir = self.layout.run_dir / f"run_{run_id}"
        snapshot_root = staging_dir / "snapshot"
        snapshot_root.mkdir(parents=True, exist_ok=True)

        # Store storage layout signals for collectors (needed for mirror exclusions)
        signals: Dict[str, Any] = {}
        signals["config.modes.network_policy"] = modes.get("network_policy", {}) or {}
        signals["config.modes.mirror_policy"] = modes.get("mirror_policy", {}) or {}
        signals["storage.install_dir"] = str(self.layout.install_dir)
        signals["storage.deps_dir"] = str(self.layout.deps_dir)
        signals["storage.cache_dir"] = str(self.layout.cache_dir)
        signals["storage.run_dir"] = str(self.layout.run_dir)
        signals["storage.reports_dir"] = str(self.layout.reports_dir)
        signals["storage.logs_dir"] = str(self.layout.logs_dir)

        # Core-level quick metrics for policy
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

        # Record run context meta early
        self._write_run_context(ctx, initiator=initiator, staging_dir=staging_dir)

        # Incremental: load index, decide baseline/delta
        idx = self.index_mgr.load()
        inc_policy = modes.get("incremental_policy", {}) or {}
        inc_enabled = bool(inc_policy.get("enabled", True))
        run_mode = "baseline"
        baseline_run_id, baseline_norm = self.index_mgr.get_baseline(idx)
        runs_since = self.index_mgr.runs_since_baseline(idx)
        signals["incremental.enabled"] = inc_enabled
        signals["incremental.baseline_run_id"] = baseline_run_id
        signals["incremental.runs_since_baseline"] = runs_since

        if inc_enabled and baseline_run_id and not force_baseline:
            run_mode = "delta"
        if inc_enabled and baseline_run_id and runs_since >= int(inc_policy.get("baseline_frequency_runs", 5)):
            # If baseline too old, suggest baseline (policy will do)
            pass
        if force_baseline or not baseline_run_id:
            run_mode = "baseline"

        self.logger.info(f"Run starting: run_id={run_id} mode={run_mode} research={research_mode} perf={performance_mode}")

        # Collectors selection
        all_collectors = collectors_by_id()
        enabled = self._select_enabled_collectors(all_collectors)

        # Run phases with dependency ordering
        phase1_ids = [
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
        phase2_ids = [
            "mvp-13-web-discovery",
            "mvp-14-sensitive-scan",
            "mvp-15-mirror",
        ]
        phase3_ids = [
            "mvp-18-diff",
        ]
        phase4_ids = [
            "mvp-16-summary",
            "mvp-17-checksums",
        ]

        results: Dict[str, Dict[str, Any]] = {}
        all_findings: List[Dict[str, Any]] = []
        normalized: Dict[str, Any] = {}

        def run_phase(ids: List[str]) -> None:
            nonlocal results, all_findings, normalized
            # Only run enabled collectors
            to_run = [enabled[cid] for cid in ids if cid in enabled]
            if not to_run:
                return
            # Concurrency
            max_conc = self._effective_concurrency(ctx)
            if max_conc <= 1 or len(to_run) == 1:
                for c in to_run:
                    if self.stop_requested():
                        break
                    r = self._run_one_collector(c, ctx)
                    results[c.META.collector_id] = r
                    all_findings.extend(r.get("findings", []) or [])
                    if "normalized_data" in r:
                        for k, v in (r.get("normalized_data") or {}).items():
                            normalized[k] = v
            else:
                with ThreadPoolExecutor(max_workers=max_conc) as ex:
                    futs = {ex.submit(self._run_one_collector, c, ctx): c for c in to_run}
                    for fut in as_completed(futs):
                        c = futs[fut]
                        if self.stop_requested():
                            break
                        try:
                            r = fut.result()
                        except Exception as e:
                            r = {"run": {"status": "error"}, "findings": [], "errors": [{"message": str(e)}]}
                        results[c.META.collector_id] = r
                        all_findings.extend(r.get("findings", []) or [])
                        if "normalized_data" in r:
                            for k, v in (r.get("normalized_data") or {}).items():
                                normalized[k] = v

        # Phase 1
        run_phase(phase1_ids)

        # Policy engine (adaptive)
        adaptive_policy = modes.get("adaptive_policy", {}) or {}
        if bool(adaptive_policy.get("enabled", True)):
            signals["core.all_findings"] = all_findings
            # add incremental baseline data if any
            signals["incremental"] = {
                "enabled": inc_enabled,
                "baseline_run_id": baseline_run_id,
                "baseline_normalized": baseline_norm,
                "current_normalized": normalized,
            }
            # For policy rules about new ports, compute diff count
            if baseline_norm and normalized and isinstance(baseline_norm.get("listening_ports"), list) and isinstance(normalized.get("listening_ports"), list):
                opened = set(normalized["listening_ports"]) - set(baseline_norm["listening_ports"])
                signals["diff.new_listening_ports_count"] = len(opened)
            require_conf = bool(adaptive_policy.get("require_confirmation_for_risky", True))
            plan = self.policy_engine.evaluate(signals, research_mode=research_mode, require_confirmation_for_risky=require_conf)
            plan_path = snapshot_root / "adaptive" / "plan.json"
            plan_path.parent.mkdir(parents=True, exist_ok=True)
            write_json(plan_path, plan)
            signals["adaptive.plan_path"] = str(plan_path.relative_to(snapshot_root))
            # Apply safe overrides (only low-risk actions auto-applied; engine already decided)
            self._apply_policy_overrides(plan, enabled, ctx)

        # Phase 2 (may include web discovery, mirror depending on config/policy)
        run_phase(phase2_ids)

        # Prepare incremental signals again for DiffCollector
        idx2 = self.index_mgr.load()
        baseline_run_id, baseline_norm = self.index_mgr.get_baseline(idx2)
        signals["incremental"] = {
            "enabled": inc_enabled,
            "baseline_run_id": baseline_run_id,
            "baseline_normalized": baseline_norm,
            "current_normalized": normalized,
        }

        # Phase 3 (diff)
        run_phase(phase3_ids)

        # Phase 4 (summary + checksums)
        signals["core.all_findings"] = all_findings
        run_phase(phase4_ids)

        # Write manifest
        status = "success" if not self.stop_requested() else "stopped"
        manifest_path = snapshot_root / "manifest.json"
        manifest = self._build_manifest(ctx, status=status, run_mode=run_mode, initiator=initiator, results=results, findings=all_findings)
        write_json(manifest_path, manifest)

        # Update incremental index (after snapshot is ready)
        if inc_enabled:
            # Store aggregate normalized with expected keys
            agg_norm = self._normalize_for_index(normalized)
            snapshot_rel = f"{run_id}/snapshot"
            idx3 = self.index_mgr.load()
            idx3 = self.index_mgr.update_run(idx3, run_id=run_id, mode=run_mode, normalized=agg_norm, snapshot_relpath=snapshot_rel)
            self.index_mgr.save(idx3)

        # Move to reports_dir and create archive
        dest_run_dir = self.layout.reports_dir / run_id
        dest_snapshot = dest_run_dir / "snapshot"
        dest_run_dir.mkdir(parents=True, exist_ok=True)
        if dest_snapshot.exists():
            shutil.rmtree(dest_snapshot)
        shutil.move(str(snapshot_root), str(dest_snapshot))
        # cleanup staging
        try:
            shutil.rmtree(staging_dir, ignore_errors=True)
        except Exception:
            pass

        archive_path = self._make_archive(dest_run_dir, dest_snapshot)

        # Record free space after
        try:
            st = os.statvfs(str(self.layout.base_path))
            self.layout.free_space_after_bytes = st.f_bavail * st.f_frsize
        except Exception:
            pass

        self.logger.info(f"Run finished: {run_id} status={status} report_dir={dest_run_dir}")
        return RunResult(run_id=run_id, status=status, snapshot_path=dest_snapshot, archive_path=archive_path, manifest_path=dest_snapshot / "manifest.json")

    # ---------- internal helpers ----------

    def _make_run_id(self) -> str:
        # yyyyMMdd_HHmmssZ_rand
        t = time.strftime("%Y%m%d_%H%M%SZ", time.gmtime())
        rand = os.urandom(3).hex()
        return f"{t}_{rand}"

    def _populate_quick_signals(self, signals: Dict[str, Any]) -> None:
        # loadavg
        try:
            la = Path("/proc/loadavg").read_text(encoding="utf-8", errors="ignore").split()
            signals["system.loadavg_1m"] = float(la[0])
            signals["system.loadavg_5m"] = float(la[1])
            signals["system.loadavg_15m"] = float(la[2])
        except Exception:
            pass
        # mem available (fallback)
        try:
            mem = Path("/proc/meminfo").read_text(encoding="utf-8", errors="ignore").splitlines()
            for ln in mem:
                if ln.startswith("MemAvailable:"):
                    kb = int(ln.split()[1])
                    signals["system.mem_available_bytes"] = kb * 1024
        except Exception:
            pass
        # USB free (preflight writes free_space_before_bytes)
        if self.layout.free_space_before_bytes is not None:
            signals["system.usb_free_bytes"] = int(self.layout.free_space_before_bytes)

        # /opt mount check (should be on USB if entware)
        signals["env.opt_on_usb"] = self._is_opt_on_usb()

    def _is_opt_on_usb(self) -> bool:
        # If /opt isn't a mountpoint, we try best-effort: check mount of /opt path and see if it is external.
        try:
            from .storage import detect_usb_mounts, find_mount_for_path, read_proc_mounts, is_external_device, is_virtual_fs
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

    def _effective_concurrency(self, ctx: CollectorContext) -> int:
        lim = ctx.limits or {}
        max_c = int(lim.get("max_concurrency", 2))
        # Adaptive reductions based on signals
        mem = ctx.signals.get("system.mem_available_bytes")
        if isinstance(mem, int) and mem < 32 * 1024 * 1024:
            return 1
        la = ctx.signals.get("system.loadavg_1m")
        if isinstance(la, float) and la > 2.0:
            return 1
        return max(1, max_c)

    def _run_one_collector(self, c: BaseCollector, ctx: CollectorContext) -> Dict[str, Any]:
        if ctx.should_stop():
            return {"run": {"status": "skipped"}, "findings": [], "artifacts": [], "normalized_data": {}}

        # Root gate
        if getattr(c.META, "requires_root", False) and hasattr(os, "geteuid") and os.geteuid() != 0:
            r = c._result_template(ctx, status="skipped")
            r["run"]["status"] = "skipped"
            r["findings"].append({
                "severity": "info",
                "code": "requires_root",
                "title": "Collector requires root",
                "details": f"Collector {c.META.collector_id} skipped because not running as root.",
                "refs": [],
            })
            c.write_result_json(ctx, r)
            return r

        self.logger.info(f"Collector start: {c.META.collector_id}")
        try:
            r = c.run(ctx)
        except Exception as e:
            self.logger.exception(f"Collector failed: {c.META.collector_id}: {e}")
            r = c._result_template(ctx, status="error")
            r["run"]["status"] = "error"
            r.setdefault("findings", []).append({
                "severity": "high",
                "code": "collector_exception",
                "title": "Collector exception",
                "details": str(e),
                "refs": [],
            })
            c.write_result_json(ctx, r)
        self.logger.info(f"Collector end: {c.META.collector_id} status={r.get('run',{}).get('status')}")
        return r

    def _apply_policy_overrides(self, plan: Dict[str, Any], enabled: Dict[str, BaseCollector], ctx: CollectorContext) -> None:
        # Only apply safe overrides (disable collectors, lower concurrency/perf) here.
        overrides = plan.get("config_overrides", {}) or {}
        disabled = overrides.get("collectors.disabled") or []
        for cid in disabled:
            if cid in enabled:
                self.logger.warning(f"Policy override: disabling collector {cid}")
                enabled.pop(cid, None)

        # performance mode override
        perf = overrides.get("performance_mode")
        if perf:
            ctx.performance_mode = str(perf)

        # concurrency override
        if "limits.max_concurrency" in overrides:
            try:
                ctx.limits["max_concurrency"] = int(overrides["limits.max_concurrency"])
            except Exception:
                pass

    def _write_run_context(self, ctx: CollectorContext, initiator: str, staging_dir: Path) -> None:
        meta = {
            "run_id": ctx.run_id,
            "generated_at": utc_now_iso(),
            "initiator": initiator,
            "research_mode": ctx.research_mode,
            "performance_mode": ctx.performance_mode,
            "redaction": {
                "enabled": ctx.redaction_enabled,
                "level": ctx.redaction_level,
            },
            "storage": self.layout.as_dict(),
            "config_path": str((self.layout.base_path / "config" / "rdct.json")),
        }
        p = ctx.snapshot_root / "meta" / "run_context.json"
        p.parent.mkdir(parents=True, exist_ok=True)
        write_json(p, meta)

    def _normalize_for_index(self, normalized: Dict[str, Any]) -> Dict[str, Any]:
        # Keep only keys used by diff engine; keep stable types.
        out: Dict[str, Any] = {}
        for k in ["packages", "process_signatures", "listening_ports", "routes_sha256", "rules_sha256", "config_sha256", "http_endpoints"]:
            if k in normalized:
                out[k] = normalized[k]
        return out

    def _build_manifest(self, ctx: CollectorContext, *, status: str, run_mode: str, initiator: str,
                        results: Dict[str, Dict[str, Any]], findings: List[Dict[str, Any]]) -> Dict[str, Any]:
        # Manifest is the single entry point.
        collectors_list = []
        for cid, r in results.items():
            collectors_list.append({
                "collector_id": cid,
                "status": r.get("run", {}).get("status"),
                "artifacts_count": len(r.get("artifacts", []) or []),
                "findings_count": len(r.get("findings", []) or []),
                "result_ref": f"logs/collectors/{cid}/result.json",
            })

        manifest = {
            "manifest_version": "1.0.0",
            "tool": {
                "name": "RDCT",
                "version": __import__("rdct").__version__,
            },
            "run": {
                "run_id": ctx.run_id,
                "start_time": None,
                "end_time": None,
                "duration_ms": None,
                "status": status,
                "initiator": initiator,
                "mode": run_mode,
            },
            "modes": {
                "research_mode": ctx.research_mode,
                "performance_mode": ctx.performance_mode,
                "redaction": {"enabled": ctx.redaction_enabled, "level": ctx.redaction_level},
            },
            "storage": self.layout.as_dict(),
            "modules": {
                "policy_engine": {"enabled": bool(self.config.get("modes", {}).get("adaptive_policy", {}).get("enabled", True))},
                "incremental_engine": {"enabled": bool(self.config.get("modes", {}).get("incremental_policy", {}).get("enabled", True))},
                "app_manager": {"enabled": bool(self.config.get("apps", {}).get("allowlist_enabled", True))},
            },
            "collectors": collectors_list,
            "adaptive": {
                "plan_ref": ctx.signals.get("adaptive.plan_path"),
                "executed_actions": [],
                "blocked_actions": [],
            },
            "incremental": {
                "enabled": bool(ctx.signals.get("incremental.enabled", False)),
                "baseline_run_id": ctx.signals.get("incremental.baseline_run_id"),
                "diff_ref": ctx.signals.get("incremental.diff_report_path"),
            },
            "summary": {
                "findings_count": len(findings),
                "top_findings_ref": "reports/top_findings.json",
                "recommendations_ref": "reports/recommendations.json",
            },
            "artifacts_index_ref": None,
        }
        return manifest

    def _make_archive(self, dest_run_dir: Path, dest_snapshot: Path) -> Optional[Path]:
        try:
            archive = dest_run_dir / f"{dest_run_dir.name}.tar.gz"
            with tarfile.open(archive, "w:gz") as tf:
                tf.add(str(dest_snapshot), arcname="snapshot")
            return archive
        except Exception as e:
            self.logger.warning(f"Archive creation failed: {e}")
            return None
