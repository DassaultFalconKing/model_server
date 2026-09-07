#!/usr/bin/env python3
"""Strict refit wrapper for reliability_grounded_harness.py.

Keeps the frozen v1 harness/evidence intact while tightening future campaign
contracts discovered during review.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

OLD_PARSER_METRIC = "parser_recognition_conditional_on_attempted_call"
NEW_PARSER_METRIC = "api_visible_parser_recognition_conditional_on_api_visible_attempted_call"
REFIT_SCHEMA_VERSION = 2


def strict_thinking_cells(args):
    cells = [
        ("auto", "thinking_off_t0_s42", 0, 42, False, args.n_think_off),
        ("auto", "thinking_on_t0_s42", 0, 42, True, args.n_think_on),
    ]
    if args.n_think_sample_off or args.n_think_sample_on:
        cells.append(
            ("auto", "thinking_off_t09_seed_omitted", 0.9, "omitted", False, args.n_think_sample_off)
        )
        cells.append(
            ("auto", "thinking_on_t09_seed_omitted", 0.9, "omitted", True, args.n_think_sample_on)
        )
    return cells


def strict_classify_campaign_a(legacy, original_classifier, trial):
    _message, calls, _finish_reason = legacy.extract_tool_calls(trial.get("response"))
    if len(calls) > 1:
        return "D_WRONG_TOOL", "expected exactly one structured tool call, got %d" % len(calls)
    return original_classifier(trial)


def strict_classify_campaign_b(legacy, original_classifier, trial):
    _message, calls, _finish_reason = legacy.extract_tool_calls(trial.get("response"))
    if trial.get("allow_no_tool") and calls:
        return "D_WRONG_TOOL", "structured tool call forbidden when no structured mapping is available"
    if len(calls) > 1:
        return "D_WRONG_TOOL", "expected at most one structured tool call, got %d" % len(calls)
    return original_classifier(trial)


def _rename_metric_keys(node):
    if isinstance(node, dict):
        items = list(node.items())
        node.clear()
        for key, value in items:
            new_key = NEW_PARSER_METRIC if key == OLD_PARSER_METRIC else key
            node[new_key] = _rename_metric_keys(value)
        return node
    if isinstance(node, list):
        return [_rename_metric_keys(item) for item in node]
    return node


def augment_summary(path):
    path = Path(path)
    data = json.loads(path.read_text(encoding="utf-8"))
    _rename_metric_keys(data)
    data["measurement_contract"] = {
        "schema_version": REFIT_SCHEMA_VERSION,
        "parser_attempt_observability": "api_visible_only",
        "parser_metric_name": NEW_PARSER_METRIC,
        "sampled_thinking_contract": "temperature=0.9, seed omitted",
        "allow_no_tool_contract": "no structured tool call may be emitted",
        "tool_call_multiplicity_contract": "campaign A requires exactly one structured call once a call is emitted",
        "frozen_v1_evidence_rewritten": False,
    }
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return data


def _load_legacy():
    legacy_path = Path(__file__).with_name("reliability_grounded_harness.py")
    spec = importlib.util.spec_from_file_location("reliability_grounded_harness_v1", legacy_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load legacy reliability harness: %s" % legacy_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _argv_value(flag, default):
    try:
        index = sys.argv.index(flag)
    except ValueError:
        return default
    if index + 1 >= len(sys.argv):
        return default
    return sys.argv[index + 1]


def install_refit(legacy):
    original_a = legacy.classify_campaign_a
    original_b = legacy.classify_campaign_b
    legacy.thinking_cells = strict_thinking_cells
    legacy.classify_campaign_a = lambda trial: strict_classify_campaign_a(legacy, original_a, trial)
    legacy.classify_campaign_b = lambda trial: strict_classify_campaign_b(legacy, original_b, trial)
    return legacy


def main():
    legacy = install_refit(_load_legacy())
    out_dir = Path(_argv_value("--out-dir", "ab-evidence/reliability-campaign-v2"))
    rc = legacy.main()
    summary_path = out_dir / "summary.json"
    if summary_path.exists():
        augment_summary(summary_path)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
