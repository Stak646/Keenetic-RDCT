from __future__ import annotations

from typing import Any, Dict, List, Set, Tuple
from ..utils import sha256_text, utc_now_iso


def _split_pkg(s: str) -> Tuple[str, str]:
    # "name=version"
    if "=" in s:
        name, ver = s.split("=", 1)
        return name, ver
    return s, ""


def diff_normalized(baseline: Dict[str, Any], target: Dict[str, Any], *, baseline_run_id: str, target_run_id: str, scope: Dict[str, Any]) -> Dict[str, Any]:
    bpkgs = set(baseline.get("packages", []))
    tpkgs = set(target.get("packages", []))

    b_map = { _split_pkg(x)[0]: _split_pkg(x)[1] for x in bpkgs }
    t_map = { _split_pkg(x)[0]: _split_pkg(x)[1] for x in tpkgs }

    added_names = sorted(set(t_map.keys()) - set(b_map.keys()))
    removed_names = sorted(set(b_map.keys()) - set(t_map.keys()))
    changed_names = sorted({n for n in set(t_map.keys()) & set(b_map.keys()) if t_map.get(n) != b_map.get(n)})

    packages_section = {
        "summary": {
            "added": len(added_names),
            "removed": len(removed_names),
            "version_changed": len(changed_names),
        },
        "added": [{"name": n, "version": t_map.get(n)} for n in added_names],
        "removed": [{"name": n, "version": b_map.get(n)} for n in removed_names],
        "changed": [{"name": n, "from_version": b_map.get(n), "to_version": t_map.get(n)} for n in changed_names],
        "refs": [],
    }

    b_procs = set(baseline.get("process_signatures", []))
    t_procs = set(target.get("process_signatures", []))
    new_procs = sorted(t_procs - b_procs)
    term_procs = sorted(b_procs - t_procs)
    processes_section = {
        "summary": {"new": len(new_procs), "terminated": len(term_procs), "changed": 0},
        "new": [{"signature": s, "cmdline_redacted": "REDACTED"} for s in new_procs[:200]],
        "terminated": [{"signature": s, "cmdline_redacted": "REDACTED"} for s in term_procs[:200]],
        "changed": [],
        "refs": [],
    }

    b_ports = set(baseline.get("listening_ports", []))
    t_ports = set(target.get("listening_ports", []))
    opened = sorted(t_ports - b_ports)
    closed = sorted(b_ports - t_ports)
    ports_section = {
        "summary": {"opened": len(opened), "closed": len(closed), "changed_owner": 0},
        "opened": [_port_obj(s) for s in opened[:500]],
        "closed": [_port_obj(s) for s in closed[:500]],
        "changed_owner": [],
        "refs": [],
    }

    b_routes = baseline.get("routes_sha256")
    t_routes = target.get("routes_sha256")
    b_rules = baseline.get("rules_sha256")
    t_rules = target.get("rules_sha256")
    routes_changed = {"added": [], "removed": [], "changed": []}
    if b_routes != t_routes:
        routes_changed["changed"].append({"from_sha256": b_routes, "to_sha256": t_routes})
    rules_changed = {"added": [], "removed": [], "changed": []}
    if b_rules != t_rules:
        rules_changed["changed"].append({"from_sha256": b_rules, "to_sha256": t_rules})
    network_section = {
        "routes_changed": routes_changed,
        "rules_changed": rules_changed,
        "dns_changed": {"added": [], "removed": [], "changed": []},
        "refs": [],
    }

    b_cfg = baseline.get("config_sha256")
    t_cfg = target.get("config_sha256")
    configs_section = {
        "summary": {"hash_changed_count": int(1 if b_cfg and t_cfg and b_cfg != t_cfg else 0)},
        "changed": [],
        "refs": [],
    }
    if b_cfg and t_cfg and b_cfg != t_cfg:
        configs_section["changed"].append({
            "path": "keenetic/config_export.txt",
            "from_sha256": b_cfg,
            "to_sha256": t_cfg,
            "sensitive": True,
            "redacted": True,
        })

    logs_section = {
        "summary": {"new_error_signatures": 0, "increased_errors": 0, "decreased_errors": 0},
        "signatures": [],
        "refs": [],
    }

    findings_delta: List[Dict[str, Any]] = []
    if opened:
        findings_delta.append({
            "severity": "medium",
            "code": "new_listening_ports",
            "title": "New listening ports detected",
            "details": f"{len(opened)} new listening ports compared to baseline.",
            "refs": [],
        })
    if added_names:
        findings_delta.append({
            "severity": "low",
            "code": "new_packages_installed",
            "title": "New packages installed",
            "details": f"{len(added_names)} new opkg packages compared to baseline.",
            "refs": [],
        })

    total_changes = len(opened) + len(closed) + len(added_names) + len(removed_names) + len(changed_names)
    report = {
        "diff_version": "1.0.0",
        "generated_at": utc_now_iso(),
        "baseline_run_id": baseline_run_id,
        "target_run_id": target_run_id,
        "mode": "baseline_vs_target",
        "scope": {
            "research_mode": scope.get("research_mode", "unknown"),
            "redaction_level": scope.get("redaction_level", "unknown"),
        },
        "stats": {
            "total_changes": int(total_changes),
            "added_count": int(len(added_names) + len(opened)),
            "removed_count": int(len(removed_names) + len(closed)),
            "changed_count": int(len(changed_names)),
            "bytes_added_estimate": None,
        },
        "sections": {
            "packages": packages_section,
            "processes": processes_section,
            "ports": ports_section,
            "network": network_section,
            "configs": configs_section,
            "logs": logs_section,
        },
        "findings_delta": findings_delta,
        "artifacts_refs": [],
        "notes": [],
    }
    return report


def _port_obj(s: str) -> Dict[str, Any]:
    # "tcp:127.0.0.1:80"
    try:
        proto, local, port_s = s.split(":", 2)
        return {"proto": proto, "local": local, "port": int(port_s), "pid": None, "process_signature": None}
    except Exception:
        return {"proto": "unknown", "local": "unknown", "port": 0, "pid": None, "process_signature": None}
