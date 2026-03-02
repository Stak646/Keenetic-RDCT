from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from ..utils import utc_now_iso


RESEARCH_ORDER = {"light": 1, "medium": 2, "full": 3, "extreme": 4}


def _gate_ok(gate_text: str, research_mode: str) -> bool:
    gt = (gate_text or "").strip().lower()
    if not gt or gt in {"always.", "always", "всегда.", "всегда"}:
        return True
    if "medium+" in gt:
        return RESEARCH_ORDER.get(research_mode, 0) >= RESEARCH_ORDER["medium"]
    if "full/extreme" in gt or "full" in gt and "extreme" in gt:
        return RESEARCH_ORDER.get(research_mode, 0) >= RESEARCH_ORDER["full"]
    if "full" in gt:
        return RESEARCH_ORDER.get(research_mode, 0) >= RESEARCH_ORDER["full"]
    return True


def _compare(value: Any, op: str, threshold: Any) -> bool:
    try:
        if op == "<":
            return float(value) < float(threshold)
        if op == "<=":
            return float(value) <= float(threshold)
        if op == ">":
            return float(value) > float(threshold)
        if op == ">=":
            return float(value) >= float(threshold)
        if op == "==":
            return value == threshold
        if op == "!=":
            return value != threshold
    except Exception:
        return False
    return False


@dataclass
class PolicyDecision:
    rule_id: str
    trigger: str
    decision: str  # auto|suggested|skipped|blocked
    reason: str
    requires_root: bool
    estimated_cost: Optional[Dict[str, Any]]
    actions: List[str]
    artifacts_refs: List[str]


class PolicyEngine:
    def __init__(self, rules_path: Path) -> None:
        self.rules_path = rules_path
        self._rules = None

    def load_rules(self) -> List[Dict[str, Any]]:
        if self._rules is not None:
            return self._rules
        data = json.loads(self.rules_path.read_text(encoding="utf-8"))
        self._rules = data.get("rules", [])
        return self._rules

    def evaluate(self, signals: Dict[str, Any], *, research_mode: str, require_confirmation_for_risky: bool) -> Dict[str, Any]:
        rules = self.load_rules()
        decisions: List[PolicyDecision] = []

        suggested_collectors: List[str] = []
        config_overrides: Dict[str, Any] = {}
        blocks: List[str] = []

        for r in rules:
            rid = r.get("id")
            gate_text = r.get("gate_text", "")
            if not _gate_ok(gate_text, research_mode):
                decisions.append(PolicyDecision(
                    rule_id=rid,
                    trigger=r.get("trigger_text_ru",""),
                    decision="skipped",
                    reason=f"gate_not_satisfied: {gate_text}",
                    requires_root=bool(r.get("requires_root", False)),
                    estimated_cost=None,
                    actions=[],
                    artifacts_refs=[],
                ))
                continue

            sig = r.get("signal")
            op = r.get("operator")
            thr = r.get("threshold")
            if not sig or not op:
                decisions.append(PolicyDecision(
                    rule_id=rid,
                    trigger=r.get("trigger_text_ru",""),
                    decision="skipped",
                    reason="no_machine_condition (documented-only rule)",
                    requires_root=bool(r.get("requires_root", False)),
                    estimated_cost=None,
                    actions=[],
                    artifacts_refs=[],
                ))
                continue
            if sig not in signals:
                decisions.append(PolicyDecision(
                    rule_id=rid,
                    trigger=r.get("trigger_text_ru",""),
                    decision="skipped",
                    reason=f"missing_signal: {sig}",
                    requires_root=bool(r.get("requires_root", False)),
                    estimated_cost=None,
                    actions=[],
                    artifacts_refs=[],
                ))
                continue

            if not _compare(signals.get(sig), op, thr):
                decisions.append(PolicyDecision(
                    rule_id=rid,
                    trigger=r.get("trigger_text_ru",""),
                    decision="skipped",
                    reason=f"condition_false: {sig} {op} {thr}",
                    requires_root=bool(r.get("requires_root", False)),
                    estimated_cost=None,
                    actions=[],
                    artifacts_refs=[],
                ))
                continue

            actions = list(r.get("actions") or [])
            risk = (r.get("risk") or "unknown").lower()
            auto_allowed = (not require_confirmation_for_risky) or (risk in {"low", "unknown"})

            decision = "auto" if auto_allowed else "suggested"
            reason = f"triggered: {sig} {op} {thr} (risk={risk})"
            decisions.append(PolicyDecision(
                rule_id=rid,
                trigger=r.get("trigger_text_ru",""),
                decision=decision,
                reason=reason,
                requires_root=bool(r.get("requires_root", False)),
                estimated_cost=None,
                actions=actions,
                artifacts_refs=[],
            ))

            # Apply actions to plan
            for a in actions:
                if a.startswith("run_collector:"):
                    suggested_collectors.append(a.split(":", 1)[1])
                elif a.startswith("disable_collector:"):
                    config_overrides.setdefault("collectors.disabled", []).append(a.split(":", 1)[1])
                elif a.startswith("set:"):
                    # set:key=value
                    kv = a.split(":", 1)[1]
                    if "=" in kv:
                        k, v = kv.split("=", 1)
                        config_overrides[k.strip()] = v.strip()
                elif a.startswith("block:"):
                    blocks.append(a.split(":", 1)[1])
                elif a.startswith("suggest:"):
                    # suggestions shown to user
                    config_overrides.setdefault("suggestions", []).append(a.split(":", 1)[1])

        plan = {
            "plan_version": "1.0.0",
            "generated_at": utc_now_iso(),
            "research_mode": research_mode,
            "decisions": [d.__dict__ for d in decisions],
            "suggested_collectors": sorted(set(suggested_collectors)),
            "config_overrides": config_overrides,
            "blocks": sorted(set(blocks)),
        }
        return plan
