from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import sha256_text, utc_now_iso, write_json


class FileSecurityInventoryCollector(BaseCollector):
    META = CollectorMeta(
        name="FileSecurityInventoryCollector",
        version="1.0",
        collector_id="ext-07-file-security",
        category="security",
        requires_root=True,
        default_enabled=False,
        risk_level=2,
        cost_level=3,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = utc_now_iso()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        out_dir = ctx.snapshot_root / "security" / "files"
        out_dir.mkdir(parents=True, exist_ok=True)

        targets = ["/opt", "/etc", "/bin", "/sbin", "/usr"]
        # Busybox find usually supports -xdev and -perm.
        suid_cmd = "find {t} -xdev -type f \\( -perm -4000 -o -perm -2000 \\) -ls 2>/dev/null | head -n 3000"
        ww_cmd = "find {t} -xdev -type f -perm -0002 -ls 2>/dev/null | head -n 3000"

        suid_texts: List[str] = []
        ww_texts: List[str] = []

        for t in targets:
            try:
                cr = self._run_cmd(ctx, ["sh", "-c", suid_cmd.format(t=t)], timeout_sec=int(ctx.limits.get("collector_timeout_sec", 60)), sensitive_output=True)
                if cr.stdout_path and Path(cr.stdout_path).exists():
                    txt = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore")
                    if txt.strip():
                        suid_texts.append(f"# {t}\n" + txt)
            except Exception:
                continue
            try:
                cr = self._run_cmd(ctx, ["sh", "-c", ww_cmd.format(t=t)], timeout_sec=int(ctx.limits.get("collector_timeout_sec", 60)), sensitive_output=True)
                if cr.stdout_path and Path(cr.stdout_path).exists():
                    txt = Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore")
                    if txt.strip():
                        ww_texts.append(f"# {t}\n" + txt)
            except Exception:
                continue

        artifacts = []
        suid_all = "\n".join(suid_texts)
        ww_all = "\n".join(ww_texts)

        if suid_all.strip():
            rel = str((out_dir / "suid_sgid.txt").relative_to(ctx.snapshot_root))
            p = self._write_text(ctx, rel, suid_all, sensitive=True)
            artifacts.append(self._register_artifact(
                ctx,
                path=p,
                type_="text",
                sensitive=True,
                redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                description="SUID/SGID files (limited)",
                tags=["files", "permissions"],
            ))
        if ww_all.strip():
            rel = str((out_dir / "world_writable.txt").relative_to(ctx.snapshot_root))
            p = self._write_text(ctx, rel, ww_all, sensitive=True)
            artifacts.append(self._register_artifact(
                ctx,
                path=p,
                type_="text",
                sensitive=True,
                redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                description="World-writable files (limited)",
                tags=["files", "permissions"],
            ))

        summary = {
            "suid_sgid_present": bool(suid_all.strip()),
            "world_writable_present": bool(ww_all.strip()),
            "suid_sha256": sha256_text(suid_all) if suid_all.strip() else None,
            "world_writable_sha256": sha256_text(ww_all) if ww_all.strip() else None,
        }
        sum_path = out_dir / "file_security_summary.json"
        write_json(sum_path, summary)
        artifacts.append(self._register_artifact(
            ctx,
            path=sum_path,
            type_="json",
            sensitive=False,
            redacted=False,
            description="File security summary",
            tags=["files", "permissions"],
        ))

        if summary["suid_sgid_present"]:
            result.setdefault("findings", []).append(
                {
                    "severity": "medium",
                    "code": "suid_files_present",
                    "title": "SUID/SGID binaries present",
                    "details": "One or more SUID/SGID files were found. Review for unexpected Entware binaries.",
                    "refs": [{"path": str(sum_path.relative_to(ctx.snapshot_root)), "type": "artifact"}],
                }
            )

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {
            "suid_sha256": summary.get("suid_sha256"),
            "world_writable_sha256": summary.get("world_writable_sha256"),
        }
        result["stats"]["items_collected"] = int(summary["suid_sgid_present"]) + int(summary["world_writable_present"])
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = sum((ctx.snapshot_root / a["path"]).stat().st_size for a in artifacts if a.get("path"))

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
