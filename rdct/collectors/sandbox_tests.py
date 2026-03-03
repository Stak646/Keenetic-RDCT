from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List

from .base import BaseCollector, CollectorContext, CollectorMeta
from ..utils import utc_now_iso, write_json


class SandboxTestsCollector(BaseCollector):
    META = CollectorMeta(
        name="SandboxTestsCollector",
        version="1.0",
        collector_id="ext-15-sandbox-tests",
        category="system",
        requires_root=False,
        default_enabled=False,
        risk_level=2,
        cost_level=2,
    )

    def run(self, ctx: CollectorContext) -> Dict[str, Any]:
        started = utc_now_iso()
        result = self._result_template(ctx, status="success")
        errors: List[Dict[str, Any]] = []
        warnings: List[Dict[str, Any]] = []

        out_dir = ctx.snapshot_root / "system" / "sandbox"
        out_dir.mkdir(parents=True, exist_ok=True)

        tests: List[Dict[str, Any]] = []
        artifacts = []

        candidates = [
            ("nginx", ["nginx", "-t"], "nginx -t"),
            ("dnsmasq", ["dnsmasq", "--test"], "dnsmasq --test"),
            ("unbound-checkconf", ["unbound-checkconf"], "unbound-checkconf"),
            ("openvpn", ["openvpn", "--version"], "openvpn --version"),
        ]

        for tool, cmd, name in candidates:
            try:
                cr = self._run_cmd(ctx, cmd, timeout_sec=int(ctx.limits.get("collector_timeout_sec", 20)), sensitive_output=True)
                out = ""
                if cr.stdout_path and Path(cr.stdout_path).exists():
                    out += Path(cr.stdout_path).read_text(encoding="utf-8", errors="ignore")
                if cr.stderr_path and Path(cr.stderr_path).exists():
                    err = Path(cr.stderr_path).read_text(encoding="utf-8", errors="ignore")
                    if err.strip():
                        out += "\n" + err
                if not out.strip():
                    continue
                rel = str((out_dir / f"{tool}.txt").relative_to(ctx.snapshot_root))
                p = self._write_text(ctx, rel, out, sensitive=True)
                artifacts.append(self._register_artifact(
                    ctx,
                    path=p,
                    type_="text",
                    sensitive=True,
                    redacted=bool(ctx.redaction_enabled and ctx.research_mode in {"light", "medium"}),
                    description=f"Sandbox test output: {name}",
                    tags=["sandbox"],
                ))
                tests.append({"tool": tool, "command": cmd, "exit_code": cr.exit_code, "output_path": str(p.relative_to(ctx.snapshot_root))})
            except Exception:
                continue

        out_path = out_dir / "sandbox_tests.json"
        write_json(out_path, {"generated_at": utc_now_iso(), "tests": tests})
        artifacts.append(self._register_artifact(
            ctx,
            path=out_path,
            type_="json",
            sensitive=True,
            redacted=bool(ctx.redaction_enabled),
            description="Sandbox test report",
            tags=["sandbox"],
        ))

        if not tests:
            result["run"]["status"] = "partial"

        result["artifacts"].extend(artifacts)
        result["normalized_data"] = {"sandbox_tests_ran": len(tests)}
        result["stats"]["items_collected"] = len(tests)
        result["stats"]["files_written"] = len(artifacts)
        result["stats"]["bytes_written"] = sum((ctx.snapshot_root / a["path"]).stat().st_size for a in artifacts if a.get("path"))

        self._finalize_result(ctx, result, started)
        self.write_result_json(ctx, result)
        self.write_errors_json(ctx, errors, warnings)
        return result
