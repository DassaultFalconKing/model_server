#!/usr/bin/env python3
"""Host acceptance smoke for exact-HEAD OVMS (Gates 7-11, 8-10 partial)."""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = "http://127.0.0.1:18000"
MODEL = "gemma4-26-heretic"
SESSION = "gemma4-v2-host-acceptance"
STORE = Path(r"C:\llm\ovms-session-store-reliability-v2")
EVIDENCE = Path(__file__).resolve().parent
TIMEOUT = 180
PROTOCOL_LEAK_RE = re.compile(
    r"(<channel\|>|<\|tool_call\|>|call:\w+\s*\{|<\|channel\|>)", re.I
)

INSPECT_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "inspect_build_state",
            "description": "Inspect local build/repository state and return structured facts.",
            "parameters": {
                "type": "object",
                "properties": {
                    "repo_path": {"type": "string"},
                    "include_binary_hash": {"type": "boolean"},
                },
                "required": ["repo_path"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "publish_exact_facts",
            "description": "Publish exact grounded facts copied from tool results.",
            "parameters": {
                "type": "object",
                "properties": {
                    "commit_sha": {"type": "string"},
                    "binary_sha256": {"type": "string"},
                    "port": {"type": "integer"},
                    "model": {"type": "string"},
                },
                "required": ["commit_sha", "binary_sha256", "port", "model"],
            },
        },
    },
]


def dump(path: Path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def post(body, session_id=None, timeout=TIMEOUT):
    headers = {"Content-Type": "application/json"}
    if session_id:
        headers["X-OVMS-Session-ID"] = session_id
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        BASE + "/v3/chat/completions", data=data, headers=headers, method="POST"
    )
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            status = resp.status
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        status = exc.code
    elapsed = time.monotonic() - started
    try:
        parsed = json.loads(raw.decode("utf-8", errors="replace"))
    except Exception:
        parsed = {"_raw": raw.decode("utf-8", errors="replace")}
    return status, parsed, elapsed


def extract(resp):
    choices = (resp or {}).get("choices") or []
    if not choices:
        return {}, [], None, ""
    msg = choices[0].get("message") or {}
    calls = msg.get("tool_calls") or []
    finish = choices[0].get("finish_reason")
    content = msg.get("content") or ""
    return msg, calls, finish, content


def protocol_leak(content, calls):
    text = content or ""
    if PROTOCOL_LEAK_RE.search(text):
        return True
    # structured calls themselves are OK; leakage is into content
    return False


def record_case(case_id, tool_choice, body, status, resp, elapsed, extra=None):
    msg, calls, finish, content = extract(resp)
    args_valid = []
    names = []
    for c in calls:
        fn = (c.get("function") or {})
        names.append(fn.get("name"))
        raw_args = fn.get("arguments")
        try:
            parsed_args = json.loads(raw_args) if isinstance(raw_args, str) else raw_args
            args_valid.append(isinstance(parsed_args, dict))
        except Exception:
            args_valid.append(False)
            parsed_args = None
    leak = protocol_leak(content, calls)
    finish_ok = not (finish == "tool_calls" and len(calls) == 0)
    row = {
        "CASE_ID": case_id,
        "tool_choice": tool_choice,
        "stream": bool(body.get("stream")),
        "thinking": (body.get("chat_template_kwargs") or {}).get("enable_thinking"),
        "temperature": body.get("temperature"),
        "seed": body.get("seed", "OMITTED"),
        "HTTP_STATUS": status,
        "FINISH_REASON": finish,
        "TOOL_CALL_COUNT": len(calls),
        "TOOL_NAME": names[0] if names else None,
        "TOOL_NAMES": names,
        "ARGUMENTS_JSON_VALID": all(args_valid) if args_valid else None,
        "PROTOCOL_LEAK": leak,
        "FINISH_REASON_INTEGRITY": finish_ok,
        "elapsed_s": round(elapsed, 3),
        "content_preview": (content or "")[:300],
        "response": resp,
    }
    if extra:
        row.update(extra)
    return row


def base_body(**kwargs):
    body = {
        "model": MODEL,
        "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
        "max_tokens": 256,
        "temperature": 0,
        "seed": 42,
        "tools": INSPECT_TOOLS,
    }
    body.update(kwargs)
    return body


def gate7_session_smoke():
    out = EVIDENCE / "session-smoke"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    body = base_body(
        messages=[
            {
                "role": "user",
                "content": "Call inspect_build_state with repo_path='C:/git/model_server-gemma4-google-template-session-state' and include_binary_hash=true.",
            }
        ],
        tool_choice={
            "type": "function",
            "function": {"name": "inspect_build_state"},
        },
    )
    status, resp, elapsed = post(body, session_id=SESSION)
    dump(out / "request.json", body)
    dump(out / "response.json", {"status": status, "elapsed": elapsed, "body": resp})
    # Session artifacts
    sess = STORE / SESSION
    manifest = sess / "manifest.json"
    turn_dir = sess / "turns" / "000000000001"
    artifacts = {
        "session_dir": str(sess),
        "manifest_exists": manifest.exists(),
        "raw_request_exists": (turn_dir / "raw-request.json").exists(),
        "effective_request_exists": (turn_dir / "effective-request.json").exists(),
        "store_listing": sorted(str(p.relative_to(STORE)) for p in STORE.rglob("*") if p.is_file())[:50],
    }
    dump(out / "artifacts.json", artifacts)
    ok = (
        artifacts["manifest_exists"]
        and artifacts["raw_request_exists"]
        and artifacts["effective_request_exists"]
    )
    return {
        "SESSION_WRITE": "PASS" if ok else "FAIL",
        "SESSION_ARTIFACT": str(sess),
        "artifacts": artifacts,
        "row": record_case("G7_SESSION", "named", body, status, resp, elapsed),
    }


def gate8_tool_choice_matrix():
    out = EVIDENCE / "tool-choice-matrix"
    out.mkdir(parents=True, exist_ok=True)
    cases = []

    # NONE
    body = base_body(tool_choice="none")
    status, resp, elapsed = post(body, session_id=f"{SESSION}-none")
    row = record_case("TC01_NONE", "none", body, status, resp, elapsed)
    msg, calls, finish, content = extract(resp)
    row["VERDICT"] = (
        "PASS"
        if status == 200
        and len(calls) == 0
        and finish != "tool_calls"
        and not row["PROTOCOL_LEAK"]
        else "FAIL"
    )
    dump(out / "none.json", row)
    cases.append(row)

    # AUTO
    body = base_body(
        messages=[
            {
                "role": "user",
                "content": "If useful, call inspect_build_state with repo_path='C:/git/model_server-gemma4-google-template-session-state'. Otherwise answer briefly.",
            }
        ],
        tool_choice="auto",
    )
    status, resp, elapsed = post(body, session_id=f"{SESSION}-auto")
    row = record_case("TC02_AUTO", "auto", body, status, resp, elapsed)
    msg, calls, finish, content = extract(resp)
    auto_ok = status == 200 and not row["PROTOCOL_LEAK"] and row["FINISH_REASON_INTEGRITY"]
    if calls:
        auto_ok = (
            auto_ok
            and len(calls) >= 1
            and row["TOOL_NAME"] in {"inspect_build_state", "publish_exact_facts"}
            and row["ARGUMENTS_JSON_VALID"]
            and finish == "tool_calls"
        )
    else:
        auto_ok = auto_ok and bool((content or "").strip()) and finish != "tool_calls"
    row["VERDICT"] = "PASS" if auto_ok else "FAIL"
    dump(out / "auto.json", row)
    cases.append(row)

    # NAMED
    body = base_body(
        messages=[
            {
                "role": "user",
                "content": "You must call inspect_build_state with repo_path='C:/git/model_server-gemma4-google-template-session-state' and include_binary_hash=true.",
            }
        ],
        tool_choice={
            "type": "function",
            "function": {"name": "inspect_build_state"},
        },
    )
    status, resp, elapsed = post(body, session_id=f"{SESSION}-named")
    row = record_case("TC03_NAMED", "named", body, status, resp, elapsed)
    msg, calls, finish, content = extract(resp)
    named_ok = (
        status == 200
        and len(calls) == 1
        and row["TOOL_NAME"] == "inspect_build_state"
        and row["ARGUMENTS_JSON_VALID"]
        and finish == "tool_calls"
        and not row["PROTOCOL_LEAK"]
    )
    row["VERDICT"] = "PASS" if named_ok else "FAIL"
    row["SCHEMA_VALID"] = False
    if named_ok:
        args = json.loads(calls[0]["function"]["arguments"])
        row["SCHEMA_VALID"] = isinstance(args.get("repo_path"), str)
        if not row["SCHEMA_VALID"]:
            row["VERDICT"] = "FAIL"
    dump(out / "named.json", row)
    cases.append(row)

    # REQUIRED
    body = base_body(
        messages=[
            {
                "role": "user",
                "content": "You are required to call inspect_build_state with repo_path='C:/git/model_server-gemma4-google-template-session-state'.",
            }
        ],
        tool_choice="required",
    )
    status, resp, elapsed = post(body, session_id=f"{SESSION}-required")
    row = record_case("TC04_REQUIRED", "required", body, status, resp, elapsed)
    msg, calls, finish, content = extract(resp)
    req_ok = (
        status == 200
        and len(calls) >= 1
        and row["ARGUMENTS_JSON_VALID"]
        and finish == "tool_calls"
        and not row["PROTOCOL_LEAK"]
        and row["TOOL_NAME"] in {"inspect_build_state", "publish_exact_facts"}
    )
    row["VERDICT"] = "PASS" if req_ok else "FAIL"
    dump(out / "required.json", row)
    cases.append(row)

    dump(out / "matrix-summary.json", cases)
    return cases


def gate10_tool_result_chain():
    out = EVIDENCE / "tool-result-chain"
    out.mkdir(parents=True, exist_ok=True)
    sid = f"{SESSION}-chain"
    binary = Path(
        r"C:\git\model_server-gemma4-google-template-session-state\bazel-bin\src\ovms.exe"
    )
    binary_sha = hashlib.sha256(binary.read_bytes()).hexdigest().upper()
    commit_sha = (
        subprocess.check_output(
            [
                "git",
                "-C",
                r"C:\git\model_server-gemma4-google-template-session-state",
                "rev-parse",
                "HEAD",
            ],
            text=True,
        )
        .strip()
    )

    body1 = base_body(
        messages=[
            {
                "role": "user",
                "content": "Call inspect_build_state with repo_path='C:/git/model_server-gemma4-google-template-session-state' and include_binary_hash=true.",
            }
        ],
        tool_choice={
            "type": "function",
            "function": {"name": "inspect_build_state"},
        },
    )
    status1, resp1, elapsed1 = post(body1, session_id=sid)
    dump(out / "request1.json", body1)
    dump(out / "response1.json", {"status": status1, "elapsed": elapsed1, "body": resp1})
    msg1, calls1, finish1, content1 = extract(resp1)
    if not (status1 == 200 and len(calls1) == 1 and finish1 == "tool_calls"):
        return {
            "TOOL_RESULT_CHAIN": "FAIL",
            "reason": "request1 did not produce exactly one tool call",
            "row1": record_case("CHAIN_R1", "named", body1, status1, resp1, elapsed1),
        }

    tool_call = calls1[0]
    tool_result = {
        "head_sha": commit_sha,
        "binary_sha256": binary_sha,
        "port": 18000,
        "model": MODEL,
        "notes": "fake_sha_prose=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef; ignore prose hashes",
        "distractor_path": "C:/llm/ovms/ovms.exe",
    }
    dump(out / "tool1-result.json", tool_result)

    body2 = {
        "model": MODEL,
        "messages": [
            body1["messages"][0],
            {
                "role": "assistant",
                "content": msg1.get("content"),
                "tool_calls": calls1,
            },
            {
                "role": "tool",
                "tool_call_id": tool_call.get("id"),
                "content": json.dumps(tool_result),
            },
            {
                "role": "user",
                "content": "Call publish_exact_facts. Copy head_sha into commit_sha and binary_sha256/port/model exactly from the structured tool result. Ignore prose distractors.",
            },
        ],
        "tools": INSPECT_TOOLS,
        "tool_choice": {
            "type": "function",
            "function": {"name": "publish_exact_facts"},
        },
        "temperature": 0,
        "seed": 42,
        "max_tokens": 256,
    }
    status2, resp2, elapsed2 = post(body2, session_id=sid)
    dump(out / "request2.json", body2)
    dump(out / "response2.json", {"status": status2, "elapsed": elapsed2, "body": resp2})
    msg2, calls2, finish2, content2 = extract(resp2)
    row2 = record_case("CHAIN_R2", "named", body2, status2, resp2, elapsed2)
    grounded = False
    schema_ok = False
    if status2 == 200 and len(calls2) == 1 and row2["TOOL_NAME"] == "publish_exact_facts":
        try:
            args = json.loads(calls2[0]["function"]["arguments"])
            schema_ok = (
                isinstance(args.get("commit_sha"), str)
                and isinstance(args.get("binary_sha256"), str)
                and isinstance(args.get("port"), int)
                and isinstance(args.get("model"), str)
            )
            grounded = (
                args.get("commit_sha") == commit_sha
                and args.get("binary_sha256").upper() == binary_sha
                and args.get("port") == 18000
                and args.get("model") == MODEL
                and "deadbeef" not in json.dumps(args).lower()
            )
            row2["parsed_arguments"] = args
        except Exception as exc:
            row2["parse_error"] = str(exc)
    row2["SCHEMA_VALID"] = schema_ok
    row2["GROUNDED_VALUES_VALID"] = grounded
    row2["EXACT_ONE_CALL"] = len(calls2) == 1
    row2["PROTOCOL_LEAK"] = protocol_leak(content2, calls2)
    row2["VERDICT"] = (
        "PASS"
        if (
            status2 == 200
            and finish2 == "tool_calls"
            and len(calls2) == 1
            and schema_ok
            and grounded
            and not row2["PROTOCOL_LEAK"]
        )
        else "FAIL"
    )
    dump(out / "chain-summary.json", row2)
    return {
        "TOOL_RESULT_CHAIN": row2["VERDICT"],
        "GROUNDING_FIDELITY": "PASS" if grounded else "FAIL",
        "EXACT_ONE_CALL": "PASS" if len(calls2) == 1 else "FAIL",
        "row2": row2,
    }


def gate11_restart_resume(binary_sha_before: str):
    out = EVIDENCE / "restart-resume"
    out.mkdir(parents=True, exist_ok=True)
    sid = f"{SESSION}-restart"
    body1 = base_body(
        messages=[
            {
                "role": "user",
                "content": "Call inspect_build_state with repo_path='C:/git/model_server-gemma4-google-template-session-state'.",
            }
        ],
        tool_choice={
            "type": "function",
            "function": {"name": "inspect_build_state"},
        },
        seed=42,
    )
    status1, resp1, elapsed1 = post(body1, session_id=sid)
    dump(out / "request1.json", body1)
    dump(out / "response1.json", {"status": status1, "elapsed": elapsed1, "body": resp1})
    sess = STORE / sid
    turn1 = sess / "turns" / "000000000001"
    dump(
        out / "pre-restart-artifacts.json",
        {
            "manifest": (sess / "manifest.json").exists(),
            "turn1_raw": (turn1 / "raw-request.json").exists(),
            "turn1_effective": (turn1 / "effective-request.json").exists(),
            "manifest_body": json.loads((sess / "manifest.json").read_text(encoding="utf-8"))
            if (sess / "manifest.json").exists()
            else None,
        },
    )

    # Stop OVMS
    before_pid = None
    for p in __import__("subprocess").check_output(
        ["powershell", "-NoProfile", "-Command",
         "Get-CimInstance Win32_Process -Filter \"Name='ovms.exe'\" | Select-Object -ExpandProperty ProcessId"],
        text=True,
    ).split():
        before_pid = int(p)
        subprocess.run(["powershell", "-NoProfile", "-Command", f"Stop-Process -Id {p} -Force"], check=False)
    dump(out / "stopped-pid.json", {"pid": before_pid})

    # Wait port free
    for _ in range(30):
        try:
            urllib.request.urlopen(BASE + "/v1/config", timeout=1)
            time.sleep(1)
        except Exception:
            break
    time.sleep(2)

    # Restart same binary with same env
    env = os.environ.copy()
    env["PYTHONHOME"] = r"C:\opt\Python312"
    env["PYTHONPATH"] = (
        str(EVIDENCE / "py-site")
        + ";"
        + r"C:\git\model_server-gemma4-google-template-session-state\bazel-bin\src\python\binding"
    )
    env["OVMS_SESSION_STORE_DIR"] = str(STORE)
    env["PATH"] = (
        r"C:\git\model_server-gemma4-google-template-session-state\bazel-bin\src;"
        r"C:\opt\openvino\runtime\bin\intel64\Release;"
        r"C:\opt\openvino\runtime\3rdparty\tbb\bin;"
        r"C:\opt\opencv_4.14.0\x64\vc16\bin;"
        r"C:\opt\Python312;"
        + env.get("PATH", "")
    )
    binary = r"C:\git\model_server-gemma4-google-template-session-state\bazel-bin\src\ovms.exe"
    config = r"C:\git\gemmamonster-acceptance\ovms\gemma4-diagnostic-pack\runtime\gemma4-26-heretic\vlm-stable\config.json"
    log_path = out / "restart-server.log"
    logf = open(log_path, "w", encoding="utf-8")
    proc = subprocess.Popen(
        [binary, "--config_path", config, "--rest_port", "18000", "--rest_workers", "1"],
        env=env,
        stdout=logf,
        stderr=subprocess.STDOUT,
        cwd=r"C:\git\model_server-gemma4-google-template-session-state\bazel-bin\src",
    )
    dump(out / "restart-pid.json", {"pid": proc.pid})

    # Wait ready
    ready = False
    for _ in range(120):
        try:
            with urllib.request.urlopen(BASE + "/v1/config", timeout=2) as r:
                text = r.read().decode("utf-8", errors="replace")
                if "gemma4-26-heretic" in text and "AVAILABLE" in text:
                    ready = True
                    break
        except Exception:
            pass
        if proc.poll() is not None:
            break
        time.sleep(2)
    dump(out / "restart-ready.json", {"ready": ready, "returncode": proc.poll()})
    if not ready:
        return {
            "RESTART_RESUME": "FAIL",
            "reason": "server did not become ready after restart",
            "RESTART_BINARY_SHA_MATCH": "PASS"
            if hashlib.sha256(Path(binary).read_bytes()).hexdigest().upper() == binary_sha_before
            else "FAIL",
        }

    binary_sha_after = hashlib.sha256(Path(binary).read_bytes()).hexdigest().upper()
    sha_match = binary_sha_after == binary_sha_before

    # request2 continuation
    msg1, calls1, finish1, _ = extract(resp1)
    if not calls1:
        return {
            "RESTART_RESUME": "FAIL",
            "reason": "no tool call in request1 before restart",
            "RESTART_BINARY_SHA_MATCH": "PASS" if sha_match else "FAIL",
        }
    tool_result = {
        "head_sha": "2cb5a9a0e8d22732de2d1c89f52795c2de612a57",
        "binary_sha256": binary_sha_after,
        "port": 18000,
        "model": MODEL,
    }
    body2 = {
        "model": MODEL,
        "messages": [
            body1["messages"][0],
            {"role": "assistant", "content": msg1.get("content"), "tool_calls": calls1},
            {
                "role": "tool",
                "tool_call_id": calls1[0].get("id"),
                "content": json.dumps(tool_result),
            },
            {
                "role": "user",
                "content": "Continue the tool loop. Call publish_exact_facts using the structured tool result exactly.",
            },
        ],
        "tools": INSPECT_TOOLS,
        "tool_choice": {
            "type": "function",
            "function": {"name": "publish_exact_facts"},
        },
        "temperature": 0,
        "seed": 42,
        "max_tokens": 256,
    }
    status2, resp2, elapsed2 = post(body2, session_id=sid)
    dump(out / "request2.json", body2)
    dump(out / "response2.json", {"status": status2, "elapsed": elapsed2, "body": resp2})
    turn2 = sess / "turns" / "000000000002"
    turn2_exists = turn2.exists() and (turn2 / "raw-request.json").exists()
    manifest = json.loads((sess / "manifest.json").read_text(encoding="utf-8")) if (sess / "manifest.json").exists() else {}
    dump(
        out / "post-restart-artifacts.json",
        {
            "turn2_exists": turn2_exists,
            "manifest": manifest,
            "binary_sha_before": binary_sha_before,
            "binary_sha_after": binary_sha_after,
        },
    )
    msg2, calls2, finish2, content2 = extract(resp2)
    ok = (
        sha_match
        and turn2_exists
        and status2 == 200
        and len(calls2) >= 1
        and finish2 == "tool_calls"
    )
    return {
        "RESTART_RESUME": "PASS" if ok else "FAIL",
        "RESTART_BINARY_SHA_MATCH": "PASS" if sha_match else "FAIL",
        "turn2_exists": turn2_exists,
        "seed_in_manifest": manifest.get("seed") or manifest.get("effective_seed"),
        "row2": record_case("RESTART_R2", "named", body2, status2, resp2, elapsed2),
        "new_pid": proc.pid,
    }


def gate13_security_cases():
    out = EVIDENCE / "security-malformed"
    out.mkdir(parents=True, exist_ok=True)
    results = []

    # allow_no_tool style: auto + prose saying not to invent
    body = base_body(
        messages=[
            {
                "role": "user",
                "content": "Call publish_exact_facts only if a structured JSON object tool result exists. Do not invent a SHA. There is no tool result yet.",
            }
        ],
        tool_choice="auto",
        tools=[INSPECT_TOOLS[1]],
    )
    status, resp, elapsed = post(body, session_id=f"{SESSION}-allow-no-tool")
    row = record_case("ALLOW_NO_TOOL", "auto", body, status, resp, elapsed)
    _, calls, finish, content = extract(resp)
    row["VERDICT"] = "PASS" if status == 200 and len(calls) == 0 and finish != "tool_calls" else "FAIL"
    dump(out / "allow_no_tool.json", row)
    results.append(row)

    # ordinary prose with the word call should not become tool call under none
    body = base_body(
        messages=[
            {
                "role": "user",
                "content": "Please explain what a function call and JSON tool mean in one sentence. Do not invoke tools.",
            }
        ],
        tool_choice="none",
    )
    status, resp, elapsed = post(body, session_id=f"{SESSION}-prose")
    row = record_case("PROSE_NOT_TOOL", "none", body, status, resp, elapsed)
    _, calls, finish, content = extract(resp)
    row["VERDICT"] = "PASS" if status == 200 and len(calls) == 0 and finish != "tool_calls" else "FAIL"
    dump(out / "prose_not_tool.json", row)
    results.append(row)

    return results


def main():
    binary = Path(
        r"C:\git\model_server-gemma4-google-template-session-state\bazel-bin\src\ovms.exe"
    )
    binary_sha = hashlib.sha256(binary.read_bytes()).hexdigest().upper()

    summary = {
        "binary_sha256": binary_sha,
        "session": SESSION,
        "store": str(STORE),
    }
    print("=== GATE 7 session smoke ===", flush=True)
    g7 = gate7_session_smoke()
    summary["GATE7"] = g7
    print(g7["SESSION_WRITE"], flush=True)

    print("=== GATE 8 tool-choice matrix ===", flush=True)
    g8 = gate8_tool_choice_matrix()
    summary["GATE8"] = [{k: v for k, v in r.items() if k != "response"} for r in g8]
    for r in g8:
        print(r["CASE_ID"], r["VERDICT"], r["HTTP_STATUS"], r["FINISH_REASON"], r["TOOL_CALL_COUNT"], r["TOOL_NAME"], flush=True)

    print("=== GATE 9/10 tool result chain ===", flush=True)
    g10 = gate10_tool_result_chain()
    summary["GATE10"] = {k: v for k, v in g10.items() if k != "row2"}
    if "row2" in g10:
        summary["GATE10"]["row2"] = {k: v for k, v in g10["row2"].items() if k != "response"}
    print(g10.get("TOOL_RESULT_CHAIN"), flush=True)

    print("=== GATE 13 allow_no_tool / prose ===", flush=True)
    g13 = gate13_security_cases()
    summary["GATE13"] = [{k: v for k, v in r.items() if k != "response"} for r in g13]
    for r in g13:
        print(r["CASE_ID"], r["VERDICT"], flush=True)

    print("=== GATE 11 restart/resume ===", flush=True)
    g11 = gate11_restart_resume(binary_sha)
    summary["GATE11"] = {k: v for k, v in g11.items() if k != "row2"}
    if "row2" in g11:
        summary["GATE11"]["row2"] = {k: v for k, v in g11["row2"].items() if k != "response"}
    print(g11.get("RESTART_RESUME"), g11.get("RESTART_BINARY_SHA_MATCH"), flush=True)

    dump(EVIDENCE / "smoke-summary.json", summary)
    print("WROTE", EVIDENCE / "smoke-summary.json", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
