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

SOURCE_SHA = "source_sha"
GROUNDING_FIXTURE_SHA = "grounding_fixture_sha"
LEGACY_SOURCE_SHA = "git_sha"
LEGACY_FIXTURE_SHA = "production_sha"
DEPRECATED_ALIAS_KEY = "production_sha_deprecated_alias_for"


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


def normalize_provenance_record(record):
    """Add unambiguous v2 provenance fields without mutating frozen v1 evidence."""
    if not isinstance(record, dict):
        return record
    if SOURCE_SHA not in record and LEGACY_SOURCE_SHA in record:
        record[SOURCE_SHA] = record.get(LEGACY_SOURCE_SHA)
    if GROUNDING_FIXTURE_SHA not in record and LEGACY_FIXTURE_SHA in record:
        record[GROUNDING_FIXTURE_SHA] = record.get(LEGACY_FIXTURE_SHA)
    if LEGACY_FIXTURE_SHA in record:
        record[DEPRECATED_ALIAS_KEY] = GROUNDING_FIXTURE_SHA
    return record


def normalize_summary_provenance(data):
    if not isinstance(data, dict):
        return data
    provenance = data.get("provenance")
    if isinstance(provenance, dict):
        normalize_provenance_record(provenance)
    return data


def rewrite_provenance_cli_aliases(argv):
    """Accept v2 names while invoking the unchanged v1 argparse contract."""
    argv = list(argv)
    additions = []
    rewritten = [argv[0]] if argv else []
    legacy_flags = set(argv)
    index = 1
    while index < len(argv):
        arg = argv[index]
        if arg in {"--source-sha", "--grounding-fixture-sha"}:
            if index + 1 >= len(argv):
                rewritten.append(arg)
                index += 1
                continue
            value = argv[index + 1]
            target = "--git-sha" if arg == "--source-sha" else "--production-sha"
            if target not in legacy_flags:
                additions.extend([target, value])
                legacy_flags.add(target)
            index += 2
            continue
        rewritten.append(arg)
        index += 1
    return rewritten + additions


def strict_classify_campaign_a(legacy, original_classifier, trial):
    _message, calls, _finish_reason = legacy.extract_tool_calls(trial.get("response"))
    if len(calls) > 1:
        return "D_WRONG_TOOL", "expected exactly one structured tool call, got %d" % len(calls)
    outcome, reason = original_classifier(trial)
    if outcome != "PASS" or not calls:
        return outcome, reason
    source = trial.get("tool_result")
    expected = source.get("repository") if isinstance(source, dict) else None
    if isinstance(expected, str):
        arguments = calls[0].get("function", {}).get("arguments", {})
        if isinstance(arguments, str):
            arguments = json.loads(arguments)  # The original classifier validated JSON.
        repository = arguments.get("repository")
        # Accept Windows slash spelling, but never drop a drive or alter a path.
        if not isinstance(repository, str) or repository.replace("\\", "/") != expected.replace("\\", "/"):
            return "F_GROUNDED_VALUE_CORRUPTED", "repository expected %r got %r" % (expected, repository)
    return outcome, reason


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
    normalize_summary_provenance(data)
    data["measurement_contract"] = {
        "schema_version": REFIT_SCHEMA_VERSION,
        "parser_attempt_observability": "api_visible_only",
        "parser_metric_name": NEW_PARSER_METRIC,
        "sampled_thinking_contract": "temperature=0.9, seed omitted",
        "allow_no_tool_contract": "no structured tool call may be emitted",
        "tool_call_multiplicity_contract": "campaign A requires exactly one structured call once a call is emitted",
        "repository_fidelity_contract": "campaign A copies tool-result repository, allowing slash spelling only",
        "provenance_contract": "source_sha and binary_sha256 identify the actual runtime; grounding_fixture_sha identifies the historical expected fact",
        "deprecated_aliases": {LEGACY_FIXTURE_SHA: GROUNDING_FIXTURE_SHA},
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
    original_compact_trial = legacy.compact_trial
    legacy.thinking_cells = strict_thinking_cells
    legacy.classify_campaign_a = lambda trial: strict_classify_campaign_a(legacy, original_a, trial)
    legacy.classify_campaign_b = lambda trial: strict_classify_campaign_b(legacy, original_b, trial)
    legacy.compact_trial = lambda trial: normalize_provenance_record(original_compact_trial(trial))
    return legacy


def main():
    sys.argv = rewrite_provenance_cli_aliases(sys.argv)
    legacy = install_refit(_load_legacy())
    out_dir = Path(_argv_value("--out-dir", "ab-evidence/reliability-campaign-v2"))
    rc = legacy.main()
    summary_path = out_dir / "summary.json"
    if summary_path.exists():
        augment_summary(summary_path)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
