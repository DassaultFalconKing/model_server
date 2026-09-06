#!/usr/bin/env python3
"""Reproducible Gemma4 chained-tool acceptance harness.

Validates and records the exact two-request conversation for:
  1. model -> inspect_repository_state,
  2. read-only local Git execution,
  3. tool result -> publish_review_evidence,
  4. byte-exact propagation of the commit SHA.

One X-OVMS-Session-ID is reused for every turn. Sampling parameters are fixed for
one chain and recorded in session-config.json. The harness can stop after tool1,
allow OVMS to restart, then resume request2 with the same persisted session ID.
Python standard library only. The executor performs read-only Git/filesystem
operations; HTTP is limited to the configured OVMS endpoint.
"""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

CHAT_PATH = "/v3/chat/completions"
DEFAULT_TIMEOUT_S = 180
SHA40_LEN = 40
SECOND_TOOL_CHOICES = ("named", "required", "auto")
SESSION_HEADER = "X-OVMS-Session-ID"


def dump_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def run_git(repo_root, *args, check=True):
    proc = subprocess.run(
        ["git", "-C", str(repo_root), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if check and proc.returncode != 0:
        raise RuntimeError(
            "git command failed: git -C %s %s\nstdout: %s\nstderr: %s"
            % (repo_root, " ".join(args), proc.stdout, proc.stderr)
        )
    return proc


def post_json(url, body, timeout, headers=None):
    payload = json.dumps(body, separators=(",", ":")).encode("utf-8")
    request_headers = {"Content-Type": "application/json"}
    if headers:
        request_headers.update(headers)
    request = urllib.request.Request(
        url,
        data=payload,
        headers=request_headers,
        method="POST",
    )
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
            status = response.status
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        status = exc.code
    elapsed = time.monotonic() - started
    text = raw.decode("utf-8", errors="replace")
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        parsed = None
    return status, parsed, text, elapsed


def load_catalog(path):
    catalog = json.loads(path.read_text(encoding="utf-8"))
    tools = catalog.get("tools")
    if not isinstance(tools, list):
        raise ValueError("catalog must contain a tools array")
    return tools


def tool_by_name(tools, name):
    for tool in tools:
        function = tool.get("function", {}) if isinstance(tool, dict) else {}
        if function.get("name") == name:
            return tool
    raise ValueError("tool not found in catalog: %s" % name)


def first_tool_call(response):
    if not isinstance(response, dict):
        raise AssertionError("response is not a JSON object")
    choices = response.get("choices")
    if not isinstance(choices, list) or not choices:
        raise AssertionError("response has no choices")
    message = choices[0].get("message")
    if not isinstance(message, dict):
        raise AssertionError("response choice has no assistant message")
    calls = message.get("tool_calls")
    if not isinstance(calls, list) or len(calls) != 1:
        raise AssertionError("expected exactly one tool call, got %r" % calls)
    call = calls[0]
    function = call.get("function", {})
    name = function.get("name")
    arguments_raw = function.get("arguments", "")
    if not isinstance(arguments_raw, str):
        raise AssertionError("tool call arguments are not a string")
    try:
        arguments = json.loads(arguments_raw)
    except json.JSONDecodeError as exc:
        raise AssertionError("tool call arguments are invalid JSON: %s" % exc) from exc
    if not isinstance(arguments, dict):
        raise AssertionError("tool call arguments must decode to an object")
    return message, call, name, arguments


def inspect_repository_state(repo_root, requested_sha):
    before = run_git(repo_root, "status", "--porcelain=v1", "--untracked-files=all").stdout
    head_sha = run_git(repo_root, "rev-parse", "HEAD").stdout.strip()
    resolved_sha = run_git(repo_root, "rev-parse", "%s^{commit}" % requested_sha).stdout.strip()
    changed_files = [
        line
        for line in run_git(
            repo_root,
            "diff-tree",
            "--no-commit-id",
            "--name-only",
            "-r",
            resolved_sha,
        ).stdout.splitlines()
        if line
    ]
    origin = run_git(repo_root, "remote", "get-url", "origin", check=False)
    origin_url = origin.stdout.strip() if origin.returncode == 0 else None
    generated_candidates = ["bazel-bin", "bazel-out", "bazel-testlogs", "ab-evidence"]
    generated_artifacts = [name for name in generated_candidates if (repo_root / name).exists()]
    after = run_git(repo_root, "status", "--porcelain=v1", "--untracked-files=all").stdout
    if after != before:
        raise AssertionError("read-only executor changed repository status")
    return {
        "repository": str(repo_root),
        "head_sha": head_sha,
        "requested_sha": requested_sha,
        "resolved_sha": resolved_sha,
        "head_matches_requested": head_sha == resolved_sha,
        "dirty": bool(before.strip()),
        "status_porcelain": before.splitlines(),
        "changed_files": changed_files,
        "generated_artifacts": generated_artifacts,
        "origin": origin_url,
        "executor": {
            "read_only": True,
            "allow_network": False,
            "source_mutation_observed": False,
        },
    }


def require_sha(value, label):
    if not isinstance(value, str) or len(value) != SHA40_LEN or any(c not in "0123456789abcdef" for c in value):
        raise ValueError("%s must be a lowercase 40-character git SHA" % label)


def apply_sampling(request, temperature, seed, top_p, top_k):
    request["temperature"] = temperature
    if seed is not None:
        if seed < 0 or seed > 0xFFFFFFFF:
            raise ValueError("--seed must fit uint32")
        request["seed"] = seed
    if top_p is not None:
        request["top_p"] = top_p
    if top_k is not None:
        request["top_k"] = top_k
    return request


def build_request1(model, tools, repo_root, commit_sha, temperature, seed, top_p, top_k):
    user_content = (
        "Inspect repository %s at exact commit %s using inspect_repository_state. "
        "Use read-only local inspection with allow_network false. After the tool result is returned, "
        "publish a review evidence record using publish_review_evidence and copy the exact commit SHA "
        "from the tool result without changing any character."
    ) % (repo_root, commit_sha)
    request = {
        "model": model,
        "max_tokens": 768,
        "stream": False,
        "tool_choice": {"type": "function", "function": {"name": "inspect_repository_state"}},
        "tools": tools,
        "messages": [{"role": "user", "content": user_content}],
    }
    return apply_sampling(request, temperature, seed, top_p, top_k)


def second_tool_choice(mode):
    if mode == "named":
        return {"type": "function", "function": {"name": "publish_review_evidence"}}
    return mode


def build_request2(request1, assistant_message, tool_call, tool_result, tools, mode, max_tokens=1024):
    call_id = tool_call.get("id")
    if not isinstance(call_id, str) or not call_id:
        raise AssertionError("first tool call has no id")
    request = {
        "model": request1["model"],
        "max_tokens": max_tokens,
        "stream": False,
        "tool_choice": second_tool_choice(mode),
        "tools": tools,
        "messages": [
            request1["messages"][0],
            assistant_message,
            {
                "role": "tool",
                "tool_call_id": call_id,
                "name": "inspect_repository_state",
                "content": json.dumps(tool_result, separators=(",", ":"), ensure_ascii=False),
            },
        ],
    }
    for key in ("temperature", "seed", "top_p", "top_k"):
        if key in request1:
            request[key] = request1[key]
    return request


def new_session_id():
    return "gemma4-" + uuid.uuid4().hex


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--model", required=True)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--commit-sha", required=True)
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--second-tool-choice", choices=SECOND_TOOL_CHOICES, default="named")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_S)
    parser.add_argument("--session-id", default="")
    parser.add_argument("--seed", type=int, default=42,
                        help="Explicit stable uint32 seed for every turn (default: 42).")
    parser.add_argument("--omit-seed", action="store_true",
                        help="Omit seed from every request so OVMS session persistence generates/injects it.")
    parser.add_argument("--max-tokens", type=int, default=1024,
                        help="max_tokens for request2 (request1 stays 768).")
    parser.add_argument("--temperature", type=float, default=0.0)
    parser.add_argument("--top-p", type=float, default=None)
    parser.add_argument("--top-k", type=int, default=None)
    parser.add_argument("--stop-after-tool-result", action="store_true",
                        help="Persist request1/tool result then stop; restart OVMS and rerun with --resume.")
    parser.add_argument("--resume", action="store_true",
                        help="Resume request2 from an existing out-dir/session-config after an OVMS restart.")
    args = parser.parse_args()

    require_sha(args.commit_sha, "--commit-sha")
    repo_root = Path(args.repo_root).resolve()
    catalog_path = Path(args.catalog).resolve()
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    tools = load_catalog(catalog_path)
    inspect_tool = tool_by_name(tools, "inspect_repository_state")
    publish_tool = tool_by_name(tools, "publish_review_evidence")
    chain_tools = [inspect_tool, publish_tool]
    endpoint = args.base_url.rstrip("/") + CHAT_PATH

    session_config_path = out_dir / "session-config.json"
    if args.resume:
        if not session_config_path.exists():
            raise ValueError("--resume requires existing session-config.json in --out-dir")
        session_config = load_json(session_config_path)
        session_id = session_config["session_id"]
        if args.session_id and args.session_id != session_id:
            raise ValueError("--session-id conflicts with persisted resume session")
    else:
        session_id = args.session_id or new_session_id()
        requested_seed = None if args.omit_seed else args.seed
        session_config = {
            "schema_version": 1,
            "session_id": session_id,
            "header": SESSION_HEADER,
            "seed_mode": "server_persisted" if args.omit_seed else "explicit",
            "requested_seed": requested_seed,
            "temperature": args.temperature,
            "top_p": args.top_p,
            "top_k": args.top_k,
            "second_tool_choice": args.second_tool_choice,
            "model": args.model,
            "commit_sha": args.commit_sha,
        }
        dump_json(session_config_path, session_config)

    headers = {SESSION_HEADER: session_id}

    if args.resume:
        request1 = load_json(out_dir / "request1-input.json")
        response1 = load_json(out_dir / "request1-response.json")
        tool_result = load_json(out_dir / "tool1-result.json")
        assistant1, call1, name1, args1 = first_tool_call(response1)
        status1 = 200
        elapsed1 = None
    else:
        requested_seed = None if args.omit_seed else args.seed
        request1 = build_request1(
            args.model, chain_tools, repo_root, args.commit_sha,
            args.temperature, requested_seed, args.top_p, args.top_k,
        )
        dump_json(out_dir / "request1-input.json", request1)
        status1, response1, raw1, elapsed1 = post_json(endpoint, request1, args.timeout, headers=headers)
        (out_dir / "request1-response.raw").write_text(raw1, encoding="utf-8")
        if response1 is not None:
            dump_json(out_dir / "request1-response.json", response1)
        if status1 != 200:
            raise AssertionError("request1 HTTP status %s" % status1)

        assistant1, call1, name1, args1 = first_tool_call(response1)
        if name1 != "inspect_repository_state":
            raise AssertionError("request1 called %r instead of inspect_repository_state" % name1)
        if args1.get("ref") != args.commit_sha:
            raise AssertionError("request1 ref mismatch: %r" % args1.get("ref"))

        tool_result = inspect_repository_state(repo_root, args.commit_sha)
        if tool_result["resolved_sha"] != args.commit_sha:
            raise AssertionError("requested SHA resolved to a different commit")
        if tool_result["head_sha"] != args.commit_sha:
            raise AssertionError(
                "worktree HEAD %s does not match acceptance SHA %s"
                % (tool_result["head_sha"], args.commit_sha)
            )
        dump_json(out_dir / "tool1-result.json", tool_result)

        if args.stop_after_tool_result:
            checkpoint = {
                "verdict": "CHECKPOINT",
                "next_action": "restart OVMS, then rerun this command with --resume and the same --out-dir",
                "session_id": session_id,
                "commit_sha": args.commit_sha,
            }
            dump_json(out_dir / "checkpoint.json", checkpoint)
            print(json.dumps(checkpoint, indent=2))
            return 0

    request2 = build_request2(
        request1,
        assistant1,
        call1,
        tool_result,
        chain_tools,
        session_config["second_tool_choice"],
        max_tokens=args.max_tokens,
    )
    dump_json(out_dir / "request2-input.json", request2)
    status2, response2, raw2, elapsed2 = post_json(endpoint, request2, args.timeout, headers=headers)
    (out_dir / "request2-response.raw").write_text(raw2, encoding="utf-8")
    if response2 is not None:
        dump_json(out_dir / "request2-response.json", response2)
    if status2 != 200:
        raise AssertionError("request2 HTTP status %s" % status2)

    _, _, name2, args2 = first_tool_call(response2)
    if name2 != "publish_review_evidence":
        raise AssertionError("request2 called %r instead of publish_review_evidence" % name2)
    propagated_sha = args2.get("commit_sha")
    exact_sha_pass = propagated_sha == tool_result["head_sha"] == args.commit_sha
    if not exact_sha_pass:
        raise AssertionError(
            "opaque SHA propagation failed: expected %s, tool_result=%r, publish=%r"
            % (args.commit_sha, tool_result["head_sha"], propagated_sha)
        )

    summary = {
        "verdict": "PASS",
        "endpoint": endpoint,
        "model": args.model,
        "commit_sha": args.commit_sha,
        "session_id": session_id,
        "session_header": SESSION_HEADER,
        "seed_mode": session_config["seed_mode"],
        "requested_seed": session_config["requested_seed"],
        "sampling": {
            "temperature": session_config["temperature"],
            "top_p": session_config["top_p"],
            "top_k": session_config["top_k"],
        },
        "resumed_after_restart_checkpoint": bool(args.resume),
        "second_tool_choice": session_config["second_tool_choice"],
        "request1": {
            "http": status1,
            "elapsed_s": None if elapsed1 is None else round(elapsed1, 3),
            "tool": name1,
            "requested_ref_exact": args1.get("ref") == args.commit_sha,
        },
        "executor": {
            "head_sha": tool_result["head_sha"],
            "resolved_sha": tool_result["resolved_sha"],
            "read_only": True,
            "allow_network": False,
        },
        "request2": {
            "http": status2,
            "elapsed_s": round(elapsed2, 3),
            "tool": name2,
            "commit_sha": propagated_sha,
            "exact_sha_pass": exact_sha_pass,
        },
        "evidence_files": [
            "session-config.json",
            "request1-input.json",
            "request1-response.json",
            "request1-response.raw",
            "tool1-result.json",
            "request2-input.json",
            "request2-response.json",
            "request2-response.raw",
            "summary.json",
        ],
    }
    dump_json(out_dir / "summary.json", summary)
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print("FAIL: %s" % exc, file=sys.stderr)
        raise
