from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

from ..utils import stable_json_dumps, utc_now_iso, write_json


INDEX_VERSION = "1.0.0"


class IndexManager:
    def __init__(self, cache_dir: Path) -> None:
        self.cache_dir = cache_dir
        self.index_path = cache_dir / "index.json"
        self.runs_dir = cache_dir / "runs"
        self.runs_dir.mkdir(parents=True, exist_ok=True)

    def load(self) -> Dict[str, Any]:
        if not self.index_path.exists():
            return {
                "index_version": INDEX_VERSION,
                "created_at": utc_now_iso(),
                "updated_at": utc_now_iso(),
                "baseline_run_id": None,
                "runs": {},
            }
        return json.loads(self.index_path.read_text(encoding="utf-8"))

    def save(self, idx: Dict[str, Any]) -> None:
        idx["updated_at"] = utc_now_iso()
        self.index_path.parent.mkdir(parents=True, exist_ok=True)
        self.index_path.write_text(stable_json_dumps(idx) + "\n", encoding="utf-8")

    def write_run_normalized(self, run_id: str, normalized: Dict[str, Any]) -> Path:
        p = self.runs_dir / f"{run_id}.normalized.json"
        write_json(p, normalized)
        return p

    def read_run_normalized(self, run_id: str) -> Optional[Dict[str, Any]]:
        p = self.runs_dir / f"{run_id}.normalized.json"
        if not p.exists():
            return None
        return json.loads(p.read_text(encoding="utf-8"))

    def update_run(self, idx: Dict[str, Any], run_id: str, mode: str, normalized: Dict[str, Any], snapshot_relpath: str) -> Dict[str, Any]:
        run_norm_path = self.write_run_normalized(run_id, normalized)
        idx.setdefault("runs", {})[run_id] = {
            "run_id": run_id,
            "time": utc_now_iso(),
            "mode": mode,
            "normalized_path": str(run_norm_path.relative_to(self.cache_dir)),
            "snapshot_relpath": snapshot_relpath,
        }
        if mode == "baseline":
            idx["baseline_run_id"] = run_id
        return idx

    def get_baseline(self, idx: Dict[str, Any]) -> Tuple[Optional[str], Optional[Dict[str, Any]]]:
        bid = idx.get("baseline_run_id")
        if not bid:
            return None, None
        data = self.read_run_normalized(bid)
        return bid, data

    def runs_since_baseline(self, idx: Dict[str, Any]) -> int:
        bid = idx.get("baseline_run_id")
        if not bid:
            return 10**9
        # order by insertion (dict order). Not perfect but ok.
        count = 0
        found = False
        for rid in idx.get("runs", {}).keys():
            if rid == bid:
                found = True
                continue
            if found:
                count += 1
        return count
