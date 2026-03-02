from __future__ import annotations

import os
import shutil
import stat
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import redact_text, sha256_file, utc_now_iso, write_json


VIRTUAL_ROOTS = ("/proc", "/sys", "/dev", "/run", "/tmp")


def _is_within(path: Path, prefix: Path) -> bool:
    try:
        path.resolve().relative_to(prefix.resolve())
        return True
    except Exception:
        return False


def _is_hidden(name: str) -> bool:
    return name.startswith(".")


def _looks_sensitive_path(p: Path) -> bool:
    s = str(p).lower()
    if any(x in s for x in ["shadow", "passwd", "private", "secret", "token", "key", ".pem", ".key", ".p12", ".pfx"]):
        return True
    return False


def _tail_file(src: Path, dst: Path, tail_bytes: int = 131072) -> int:
    dst.parent.mkdir(parents=True, exist_ok=True)
    size = src.stat().st_size
    with src.open("rb") as f:
        if size > tail_bytes:
            f.seek(-tail_bytes, os.SEEK_END)
        data = f.read()
    with dst.open("wb") as out:
        out.write(data)
    return len(data)


class MirrorCollector(BaseCollector):
    META = CollectorMeta(
        collector_id="mvp-15-mirror",
        name="MirrorCollector",
        version="1.0.0",
        category="mirror",
        requires_root=False,
        default_enabled=False,  # mirror off by default
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = time.time()
        result = self._result_template(ctx, status="skipped")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        mp = ctx.signals.get("config.modes.mirror_policy", {})
        if not mp.get("enabled", False):
            self._finalize_result(ctx, result, started)
            self.write_result_json(ctx, result)
            self.write_errors_json(ctx, errors, warnings)
            return result

        mirror_out = ctx.snapshot_root / "mirror"
        mirror_out.mkdir(parents=True, exist_ok=True)

        roots = mp.get("roots") or ["/etc", "/opt/etc", "/var/log"]
        follow_symlinks = bool(mp.get("follow_symlinks", False))
        include_hidden = bool(mp.get("include_hidden", False))
        max_total_bytes = int(mp.get("max_total_bytes", 200 * 1024 * 1024))
        max_files = int(mp.get("max_files", 20000))
        max_depth = int(mp.get("max_depth", 12))
        max_single = int(mp.get("max_single_file_bytes", 20 * 1024 * 1024))

        sample = mp.get("sample_mode", {}) or {}
        sample_enabled = bool(sample.get("enabled", True))
        max_files_per_dir = int(sample.get("max_files_per_dir", 200))
        tail_threshold = int(sample.get("tail_threshold_bytes", 512 * 1024))
        tail_bytes = int(sample.get("tail_bytes", 128 * 1024))

        excluded_prefixes: List[Path] = []
        for key in ["storage.install_dir", "storage.deps_dir", "storage.cache_dir", "storage.run_dir", "storage.reports_dir", "storage.logs_dir"]:
            v = ctx.signals.get(key)
            if v:
                excluded_prefixes.append(Path(v))
        excluded_prefixes.append(mirror_out)

        totals = {
            "files_copied": 0,
            "bytes_copied": 0,
            "files_skipped": 0,
            "bytes_skipped_estimate": 0,
            "stubs_created": 0,
            "tail_truncated_files": 0,
        }
        stopped_reason = "none"

        entries: List[Dict[str, Any]] = []
        per_dir_count: Dict[str, int] = {}
        seen_inodes: Set[Tuple[int, int]] = set()

        def add_entry(**kw):
            entries.append(kw)

        def excluded(path: Path) -> Optional[str]:
            # 1) Exclude install/deps/cache/run/reports/logs
            for pref in excluded_prefixes:
                if _is_within(path, pref):
                    return "excluded_output_dir"
            # 3) virtual roots
            for vr in VIRTUAL_ROOTS:
                if str(path).startswith(vr + "/") or str(path) == vr:
                    return "virtual_fs"
            return None

        def depth_for(root: str, path: Path) -> int:
            try:
                rel = path.relative_to(Path(root))
                return len(rel.parts)
            except Exception:
                return 0

        for root in roots:
            root_p = Path(root)
            if not root_p.exists():
                add_entry(
                    source_path=root,
                    snapshot_path=None,
                    entry_type="other",
                    action="skipped",
                    reason_code="root_missing",
                    size_bytes=None,
                    mtime=None,
                    sha256=None,
                    depth=0,
                    sensitive=False,
                    redacted=False,
                    notes="root does not exist",
                )
                continue

            for dirpath, dirnames, filenames in os.walk(root, followlinks=follow_symlinks):
                if ctx.should_stop():
                    stopped_reason = "user_stop"
                    break

                dp = Path(dirpath)
                ddepth = depth_for(root, dp)
                if ddepth > max_depth:
                    dirnames[:] = []
                    add_entry(
                        source_path=str(dp),
                        snapshot_path=None,
                        entry_type="dir",
                        action="skipped",
                        reason_code="max_depth",
                        size_bytes=None,
                        mtime=None,
                        sha256=None,
                        depth=ddepth,
                        sensitive=False,
                        redacted=False,
                        notes="depth limit reached",
                    )
                    continue

                ex = excluded(dp)
                if ex:
                    dirnames[:] = []
                    filenames[:] = []
                    add_entry(
                        source_path=str(dp),
                        snapshot_path=None,
                        entry_type="dir",
                        action="skipped",
                        reason_code=ex,
                        size_bytes=None,
                        mtime=None,
                        sha256=None,
                        depth=ddepth,
                        sensitive=False,
                        redacted=False,
                        notes="excluded by policy",
                    )
                    continue

                if not include_hidden:
                    dirnames[:] = [d for d in dirnames if not _is_hidden(d)]
                    filenames = [f for f in filenames if not _is_hidden(f)]

                # sample_mode: max files per directory
                if sample_enabled:
                    key = str(dp)
                    per_dir_count.setdefault(key, 0)

                for fn in filenames:
                    if ctx.should_stop():
                        stopped_reason = "user_stop"
                        break
                    if totals["files_copied"] + totals["files_skipped"] >= max_files:
                        stopped_reason = "max_files"
                        break

                    src = dp / fn
                    # Exclusions
                    ex2 = excluded(src)
                    if ex2:
                        totals["files_skipped"] += 1
                        add_entry(
                            source_path=str(src),
                            snapshot_path=None,
                            entry_type="file",
                            action="skipped",
                            reason_code=ex2,
                            size_bytes=None,
                            mtime=None,
                            sha256=None,
                            depth=ddepth + 1,
                            sensitive=False,
                            redacted=False,
                            notes="excluded by policy",
                        )
                        continue

                    if sample_enabled:
                        key = str(dp)
                        per_dir_count[key] += 1
                        if per_dir_count[key] > max_files_per_dir:
                            totals["files_skipped"] += 1
                            add_entry(
                                source_path=str(src),
                                snapshot_path=None,
                                entry_type="file",
                                action="skipped",
                                reason_code="sample_mode_max_files_per_dir",
                                size_bytes=None,
                                mtime=None,
                                sha256=None,
                                depth=ddepth + 1,
                                sensitive=False,
                                redacted=False,
                                notes="sample mode limit per directory",
                            )
                            continue

                    try:
                        st = src.lstat()
                    except Exception as e:
                        totals["files_skipped"] += 1
                        add_entry(
                            source_path=str(src),
                            snapshot_path=None,
                            entry_type="other",
                            action="skipped",
                            reason_code="read_error",
                            size_bytes=None,
                            mtime=None,
                            sha256=None,
                            depth=ddepth + 1,
                            sensitive=False,
                            redacted=False,
                            notes=str(e)[:200],
                        )
                        continue

                    if stat.S_ISLNK(st.st_mode) and not follow_symlinks:
                        totals["files_skipped"] += 1
                        add_entry(
                            source_path=str(src),
                            snapshot_path=None,
                            entry_type="symlink",
                            action="skipped",
                            reason_code="symlink_not_followed",
                            size_bytes=None,
                            mtime=None,
                            sha256=None,
                            depth=ddepth + 1,
                            sensitive=False,
                            redacted=False,
                            notes="symlink skipped",
                        )
                        continue

                    if follow_symlinks:
                        try:
                            rst = src.stat()
                            inode_key = (rst.st_dev, rst.st_ino)
                            if inode_key in seen_inodes:
                                totals["files_skipped"] += 1
                                add_entry(
                                    source_path=str(src),
                                    snapshot_path=None,
                                    entry_type="symlink",
                                    action="skipped",
                                    reason_code="symlink_cycle",
                                    size_bytes=None,
                                    mtime=None,
                                    sha256=None,
                                    depth=ddepth + 1,
                                    sensitive=False,
                                    redacted=False,
                                    notes="cycle detected",
                                )
                                continue
                            seen_inodes.add(inode_key)
                        except Exception:
                            pass

                    size = int(getattr(st, "st_size", 0))
                    totals["bytes_skipped_estimate"] += 0

                    sensitive = _looks_sensitive_path(src)
                    if ctx.research_mode in {"light", "medium"} and sensitive:
                        # Stub in Light/Medium
                        stub = mirror_out / str(src).lstrip("/").replace("/", "__") + ".stub.txt"
                        stub.parent.mkdir(parents=True, exist_ok=True)
                        stub.write_text("REDACTED (sensitive file stub)\n", encoding="utf-8")
                        totals["stubs_created"] += 1
                        totals["files_skipped"] += 1
                        add_entry(
                            source_path=str(src),
                            snapshot_path=str(stub.relative_to(ctx.snapshot_root)),
                            entry_type="file",
                            action="stubbed",
                            reason_code="sensitive_in_light",
                            size_bytes=size,
                            mtime=utc_now_iso(),
                            sha256=None,
                            depth=ddepth + 1,
                            sensitive=True,
                            redacted=True,
                            notes="stub created due to sensitive policy",
                        )
                        continue

                    # max_single
                    if size > max_single:
                        meta = mirror_out / str(src).lstrip("/").replace("/", "__") + ".metadata.json"
                        write_json(meta, {"source_path": str(src), "size_bytes": size, "note": "metadata only (too large)"})
                        totals["stubs_created"] += 1
                        totals["files_skipped"] += 1
                        add_entry(
                            source_path=str(src),
                            snapshot_path=str(meta.relative_to(ctx.snapshot_root)),
                            entry_type="file",
                            action="metadata_only",
                            reason_code="too_large_single",
                            size_bytes=size,
                            mtime=utc_now_iso(),
                            sha256=None,
                            depth=ddepth + 1,
                            sensitive=False,
                            redacted=False,
                            notes="single file too large",
                        )
                        continue

                    # max_total_bytes
                    if totals["bytes_copied"] + size > max_total_bytes:
                        if sample_enabled and size > tail_threshold and src.suffix.lower() in {".log", ".txt"}:
                            # Tail copy
                            dst = mirror_out / str(src).lstrip("/")
                            copied = _tail_file(src, dst, tail_bytes=tail_bytes)
                            totals["files_copied"] += 1
                            totals["bytes_copied"] += copied
                            totals["tail_truncated_files"] += 1
                            add_entry(
                                source_path=str(src),
                                snapshot_path=str(dst.relative_to(ctx.snapshot_root)),
                                entry_type="file",
                                action="tailed",
                                reason_code="max_total_bytes_tail",
                                size_bytes=size,
                                mtime=utc_now_iso(),
                                sha256=None,
                                depth=ddepth + 1,
                                sensitive=False,
                                redacted=False,
                                notes=f"tailed to {copied} bytes",
                            )
                            continue
                        # Otherwise stop or skip
                        stopped_reason = "max_total_bytes"
                        totals["files_skipped"] += 1
                        add_entry(
                            source_path=str(src),
                            snapshot_path=None,
                            entry_type="file",
                            action="skipped",
                            reason_code="max_total_bytes",
                            size_bytes=size,
                            mtime=utc_now_iso(),
                            sha256=None,
                            depth=ddepth + 1,
                            sensitive=False,
                            redacted=False,
                            notes="budget exceeded",
                        )
                        break

                    # Copy file
                    dst = mirror_out / str(src).lstrip("/")
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    try:
                        shutil.copy2(str(src), str(dst), follow_symlinks=follow_symlinks)
                        totals["files_copied"] += 1
                        totals["bytes_copied"] += size
                        add_entry(
                            source_path=str(src),
                            snapshot_path=str(dst.relative_to(ctx.snapshot_root)),
                            entry_type="file",
                            action="copied",
                            reason_code="ok",
                            size_bytes=size,
                            mtime=utc_now_iso(),
                            sha256=None,
                            depth=ddepth + 1,
                            sensitive=False,
                            redacted=False,
                            notes="copied",
                        )
                    except PermissionError as e:
                        totals["files_skipped"] += 1
                        add_entry(
                            source_path=str(src),
                            snapshot_path=None,
                            entry_type="file",
                            action="skipped",
                            reason_code="permission_denied",
                            size_bytes=size,
                            mtime=utc_now_iso(),
                            sha256=None,
                            depth=ddepth + 1,
                            sensitive=False,
                            redacted=False,
                            notes=str(e)[:200],
                        )
                    except Exception as e:
                        totals["files_skipped"] += 1
                        add_entry(
                            source_path=str(src),
                            snapshot_path=None,
                            entry_type="file",
                            action="skipped",
                            reason_code="read_error",
                            size_bytes=size,
                            mtime=utc_now_iso(),
                            sha256=None,
                            depth=ddepth + 1,
                            sensitive=False,
                            redacted=False,
                            notes=str(e)[:200],
                        )

                if stopped_reason in {"max_files", "max_total_bytes", "user_stop"}:
                    break

            if stopped_reason in {"max_files", "max_total_bytes", "user_stop"}:
                break

        mirror_index = {
            "mirror_index_version": "1.0.0",
            "generated_at": utc_now_iso(),
            "run_id": ctx.run_id,
            "mirror": {
                "roots": roots,
                "output_dir": "mirror/",
                "policy": {
                    "max_total_bytes": max_total_bytes,
                    "max_files": max_files,
                    "max_depth": max_depth,
                    "max_single_file_bytes": max_single,
                    "follow_symlinks": follow_symlinks,
                    "sample_mode_enabled": sample_enabled,
                    "max_files_per_dir": max_files_per_dir,
                    "tail_threshold_bytes": tail_threshold,
                    "tail_bytes": tail_bytes,
                    "tail_lines": int(sample.get("tail_lines", 0)),
                },
                "totals": totals,
                "stopped_reason": stopped_reason,
            },
            "entries": entries,
            "warnings": warnings,
            "errors": errors,
        }

        idx_path = mirror_out / "mirror_index.json"
        stats_path = mirror_out / "mirror_stats.json"
        write_json(idx_path, mirror_index)
        write_json(stats_path, {"totals": totals, "stopped_reason": stopped_reason})

        result["run"]["status"] = "success" if totals["files_copied"] else "partial"
        result["stats"]["items_collected"] = totals["files_copied"]
        result["stats"]["files_written"] = 2  # plus copied files (not counted here)
        result["stats"]["bytes_written"] = idx_path.stat().st_size + stats_path.stat().st_size
        result["artifacts"].append({
            "path": str(idx_path.relative_to(ctx.snapshot_root)),
            "type": "json",
            "size_bytes": idx_path.stat().st_size,
            "sha256": None,
            "sensitive": True,
            "redacted": bool(ctx.redaction_enabled and ctx.research_mode in {"light","medium"}),
            "description": "Mirror index (what was copied/skipped and why)",
        })
        result["artifacts"].append({
            "path": str(stats_path.relative_to(ctx.snapshot_root)),
            "type": "json",
            "size_bytes": stats_path.stat().st_size,
            "sha256": None,
            "sensitive": False,
            "redacted": False,
            "description": "Mirror totals and stop reason",
        })

        result["normalized_data"] = {
            "mirror_files_copied": totals["files_copied"],
            "mirror_bytes_copied": totals["bytes_copied"],
        }

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
