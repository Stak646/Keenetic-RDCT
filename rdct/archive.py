from __future__ import annotations

import os
import shutil
import tarfile
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

from .utils import sha256_file, stable_json_dumps, utc_now_iso, write_json
from .redaction import redact_file_to


CHECKSUMS_FILENAME = "checksums.sha256"


@dataclass
class ChecksumsResult:
    algorithm: str
    file: str
    covered_files_count: int


def iter_files(root: Path) -> Iterable[Path]:
    for p in root.rglob("*"):
        if p.is_file():
            yield p


def compute_checksums(snapshot_root: Path, *, exclude_names: Optional[set[str]] = None) -> Tuple[ChecksumsResult, List[Tuple[str, str]]]:
    """Compute sha256 for every file inside snapshot_root.

    Returns (checksums_meta, entries)
      - entries: list[(sha256, relative_path)]
    """
    exclude_names = exclude_names or {CHECKSUMS_FILENAME}
    entries: List[Tuple[str, str]] = []
    for p in sorted(iter_files(snapshot_root)):
        if p.name in exclude_names:
            continue
        rel = str(p.relative_to(snapshot_root))
        h = sha256_file(p)
        entries.append((h, rel))
    meta = ChecksumsResult(algorithm="sha256", file=CHECKSUMS_FILENAME, covered_files_count=len(entries))
    return meta, entries


def write_checksums_file(snapshot_root: Path, entries: List[Tuple[str, str]]) -> Path:
    out = snapshot_root / CHECKSUMS_FILENAME
    lines = [f"{h}  {rel}" for (h, rel) in entries]
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out


def make_tar_gz(src_dir: Path, dest_file: Path, *, arcname: str = "snapshot") -> Path:
    dest_file.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(dest_file, "w:gz") as tf:
        tf.add(str(src_dir), arcname=arcname)
    return dest_file


def create_redacted_export(
    *,
    snapshot_root: Path,
    out_dir: Path,
    redaction_level: str,
    base_archive_name: str,
) -> Dict[str, str]:
    """Create a redacted export bundle.

    It creates a new snapshot copy with redaction applied and re-generates checksums.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    export_id = f"export_{redaction_level}_{utc_now_iso().replace(':','').replace('.','')}"
    export_snapshot = out_dir / export_id / "snapshot"
    export_snapshot.mkdir(parents=True, exist_ok=True)

    # Copy/redact files
    notes: List[Dict[str, str]] = []
    for src in iter_files(snapshot_root):
        rel = src.relative_to(snapshot_root)
        if rel.name == CHECKSUMS_FILENAME:
            continue
        dst = export_snapshot / rel
        ok, note = redact_file_to(src, dst, level=redaction_level)
        if not ok:
            notes.append({"file": str(rel), "note": note})

    # Recompute checksums and write
    meta, entries = compute_checksums(export_snapshot)
    write_checksums_file(export_snapshot, entries)

    # Write export meta
    meta_path = export_snapshot / "meta" / "export_meta.json"
    write_json(meta_path, {
        "export_version": "1.0.0",
        "created_at": utc_now_iso(),
        "redaction_level": redaction_level,
        "notes": notes,
        "checksums": {
            "algorithm": meta.algorithm,
            "file": meta.file,
            "covered_files_count": meta.covered_files_count,
        },
    })

    # Archive
    archive_path = out_dir / export_id / f"{base_archive_name}.redacted.{redaction_level}.tar.gz"
    make_tar_gz(export_snapshot, archive_path, arcname="snapshot")
    return {
        "export_id": export_id,
        "snapshot_path": str(export_snapshot),
        "archive_path": str(archive_path),
        "meta_path": str(meta_path.relative_to(export_snapshot)),
    }
