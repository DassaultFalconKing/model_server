"""Replay frozen reliability requests unchanged; write fresh, separately classified evidence."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

import reliability_grounded_harness_v2 as v2


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--endpoint", default="http://127.0.0.1:18000/v3/chat/completions")
    parser.add_argument("trials", nargs="+")
    args = parser.parse_args()
    # Successful frozen trials need not have raw/ directories.
    index = {row["trial_id"]: row for row in (
        json.loads(line) for line in (args.source.parent / "trials.jsonl").read_text(encoding="utf-8").splitlines()
        if line.strip())}
    frozen_trials = []
    for name in args.trials:
        raw = args.source / name / "trial.json"
        frozen_trials.append(json.loads(raw.read_text(encoding="utf-8")) if raw.exists() else index[name])
    args.out.mkdir(parents=True, exist_ok=False)
    legacy = v2.install_refit(v2._load_legacy())
    provenance = {
        "source": str(args.source.resolve()),
        "head": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "binary": str(args.binary.resolve()),
        "binary_sha256": hashlib.sha256(args.binary.read_bytes()).hexdigest(),
        "endpoint": args.endpoint,
        "working_tree_patch": subprocess.check_output(["git", "diff", "--", "src"], text=True),
    }
    (args.out / "provenance.json").write_text(json.dumps(provenance, indent=2), encoding="utf-8")
    summary = []
    for name, frozen in zip(args.trials, frozen_trials):
        trial = dict(frozen)
        for key in ("intended_parsed", "grounded_exact"):
            trial.pop(key, None)
        trial.update(git_sha=provenance["head"], binary_path=provenance["binary"],
                     binary_sha256=provenance["binary_sha256"], endpoint=args.endpoint,
                     source_is_dirty=bool(provenance["working_tree_patch"]))
        trial.update(legacy.run_trial(args.endpoint, frozen["request"], 240))
        classifier = legacy.classify_campaign_a if trial["campaign"] == "A" else legacy.classify_campaign_b
        outcome, reason = classifier(trial)
        # Match the runner's no-call branch while retaining transport/truncation failures.
        if (trial.get("allow_no_tool") and trial.get("http_status") == 200
                and trial.get("finish_reason") == "stop" and not trial.get("structured_tool_calls")
                and not trial.get("protocol_attempt")):
            outcome, reason = "PASS", "no mapping available; no structured call"
        trial.update(primary_outcome=outcome, outcome_reason=reason)
        (args.out / (name + ".json")).write_text(json.dumps(trial, indent=2), encoding="utf-8")
        row = dict(trial=name, before=frozen["primary_outcome"], after=outcome,
                   reason=reason, finish=trial.get("finish_reason"), tokens=trial.get("completion_tokens"))
        summary.append(row)
        print(json.dumps(row), flush=True)
        (args.out / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
