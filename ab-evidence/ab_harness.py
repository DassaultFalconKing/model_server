#!/usr/bin/env python3
"""Gemma4 final-review A/B harness (Stage A/B reusable).

Python standard library only. No third-party imports.
Manages OVMS child lifecycle, polls readiness with a bounded deadline,
runs a deterministic 13-case corpus, and saves exact requests + raw
responses + per-case analysis. Reusable for variant A and B via CLI args.

Usage (Stage A baseline):
  C:/opt/Python312/python.exe ab_harness.py --variant A ^
    --binary C:/git/model_server-gemma4-fast/bazel-bin/src/ovms.exe ^
    --model-path C:/llm/models/OpenVINO/Wondernutts/gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov ^
    --model-name gemma4-26-heretic --rest-port 18000 --grpc-port 19000 ^
    --catalog complex-tool-catalog.json --evidence-dir stage-A --session-id <uuid>
"""
import argparse
import copy
import hashlib
import json
import os
import socket
import subprocess
import sys
import time
import traceback
import urllib.request
import urllib.error
import uuid

REQUEST_TIMEOUT_S = 180
READINESS_TIMEOUT_S = 180
CHAT_PATH = "/v3/chat/completions"
SEED = 42
TEMPERATURE = 0

MARKERS = [
    "<|tool_call|>",
    "<tool_call|>",
    "<|tool_call>",
    "<tool_call>",
    "<|channel|>",
    "<channel|>",
    "<|turn|>",
    "<turn|>",
    "<|tool_response|>",
    "<tool_response|>",
]

PATH_PREPEND = [
    r"C:\llm\ovms\python",
    r"C:\opt\openvino\runtime\bin",
    r"C:\opt\openvino\runtime\3rdparty\tbb\bin",
    r"C:\opt\opencv_4.14.0\x64\vc17\bin",
    r"C:\opt\Python312",
    r"C:\git\model_server-gemma4-fast",
]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def port_is_free(port, host="127.0.0.1"):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect((host, port))
        s.close()
        return False  # something listening
    except OSError:
        return True


def http_json(method, url, body=None, timeout=REQUEST_TIMEOUT_S):
    data = None
    headers = {"Content-Type": "application/json"}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            return resp.status, raw, time.monotonic() - t0, None
    except urllib.error.HTTPError as e:
        try:
            raw = e.read()
        except Exception:
            raw = b""
        return e.code, raw, time.monotonic() - t0, "HTTPError"
    except Exception as e:
        return -1, b"", time.monotonic() - t0, "%s: %s" % (type(e).__name__, e)


def http_get_raw(url, timeout=10):
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        try:
            return e.code, e.read()
        except Exception:
            return e.code, b""
    except Exception as e:
        return -1, ("HARNESS_ERROR %s: %s" % (type(e).__name__, e)).encode()


def find_markers(text):
    if not isinstance(text, str):
        return []
    return [m for m in MARKERS if m in text]


def build_cases(catalog_tools):
    by_name = {}
    for t in catalog_tools:
        try:
            by_name[t["function"]["name"]] = t
        except Exception:
            pass
    catalog = copy.deepcopy(catalog_tools)
    param_tool = {
        "type": "function",
        "function": {
            "name": "get_server_time",
            "description": "Return server time. Takes no parameters.",
            "parameters": {"type": "object", "properties": {}},
        },
    }
    echo_tool = {
        "type": "function",
        "function": {
            "name": "echo_marker",
            "description": "Echo text back verbatim.",
            "parameters": {
                "type": "object",
                "properties": {"text": {"type": "string"}},
                "required": ["text"],
            },
        },
    }
    named_nested_prompt = (
        "Call run_runtime_acceptance with a fully nested configuration: "
        "binary C:/git/model_server-gemma4-fast/bazel-bin/src/ovms.exe, model gemma4-26-heretic, "
        "model_path C:/llm/models/OpenVINO/Wondernutts/gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov, "
        "endpoints rest_port 18000 grpc_port 19000 health_path /v2/health/ready chat_path /v3/chat/completions, "
        "cases health/unary_chat/streaming_chat/forced_nested_tool_call/tool_round_trip with temperature 0, "
        "tool_policy tool_choice auto reject_raw_markup true. Provide all required nested objects."
    )
    cases = [
        {
            "name": "01-unary-text",
            "stream": False,
            "max_tokens": 256,
            "body": {
                "model": "__MODEL__",
                "temperature": TEMPERATURE,
                "seed": SEED,
                "max_tokens": 256,
                "stream": False,
                "messages": [
                    {"role": "user", "content": "Explain in two sentences what OpenVINO Model Server does."}
                ],
            },
            "expect": "non_empty_content, finish stop, no tool calls",
            "notes": "Baseline text generation contract.",
        },
        {
            "name": "02-streaming-text",
            "stream": True,
            "max_tokens": 256,
            "body": {
                "model": "__MODEL__",
                "temperature": TEMPERATURE,
                "seed": SEED,
                "max_tokens": 256,
                "stream": True,
                "messages": [
                    {"role": "user", "content": "In exactly three short sentences, describe what a chat template does."}
                ],
            },
            "expect": "SSE chunks ending with [DONE], reconstructed content non-empty",
            "notes": "Streaming wire contract; reconstruct every chunk.",
        },
        {
            "name": "03-auto-tool",
            "stream": False,
            "max_tokens": 512,
            "body": {
                "model": "__MODEL__",
                "temperature": TEMPERATURE,
                "seed": SEED,
                "max_tokens": 512,
                "stream": False,
                "tool_choice": "auto",
                "tools": catalog,
                "messages": [
                    {
                        "role": "user",
                        "content": "Inspect repository C:/git/g4-final-review at ref be410567f2b3f8146eda87087beb59b67199c893. "
                        "Include status and diff scopes, read_only true, allow_network false, fail_on_dirty false.",
                    }
                ],
            },
            "expect": "model decides; either stop with text or tool_calls; wire contract must hold either way",
            "notes": "Auto selection: native unconstrained generation; parser validates.",
        },
        {
            "name": "04-named-nested",
            "stream": False,
            "max_tokens": 768,
            "body": {
                "model": "__MODEL__",
                "temperature": TEMPERATURE,
                "seed": SEED,
                "max_tokens": 768,
                "stream": False,
                "tool_choice": {"type": "function", "function": {"name": "run_runtime_acceptance"}},
                "tools": catalog,
                "messages": [{"role": "user", "content": named_nested_prompt}],
            },
            "expect": "exactly the named tool, nested objects/arrays valid JSON",
            "notes": "Named nested call with four-tool catalog. Do not confuse schema-internal case enums with executed tests.",
        },
        {
            "name": "05-required-call",
            "stream": False,
            "max_tokens": 512,
            "body": {
                "model": "__MODEL__",
                "temperature": TEMPERATURE,
                "seed": SEED,
                "max_tokens": 512,
                "stream": False,
                "tool_choice": "required",
                "tools": catalog,
                "messages": [
                    {
                        "role": "user",
                        "content": "Publish a review evidence record for repository C:/git/g4-final-review commit "
                        "be410567f2b3f8146eda87087beb59b67199c893 verdict PARTIAL with one runtime_log artifact.",
                    }
                ],
            },
            "expect": "at least one tool call, finish_reason tool_calls",
            "notes": "Required forces a call from generation position zero.",
        },
        {
            "name": "06-none",
            "stream": False,
            "max_tokens": 256,
            "body": {
                "model": "__MODEL__",
                "temperature": TEMPERATURE,
                "seed": SEED,
                "max_tokens": 256,
                "stream": False,
                "tool_choice": "none",
                "tools": catalog,
                "messages": [
                    {
                        "role": "user",
                        "content": "Inspect repository C:/git/g4-final-review at ref be410567f2b3f8146eda87087beb59b67199c893 "
                        "and summarize in plain text without calling any tool.",
                    }
                ],
            },
            "expect": "no tool_calls, plain text stop",
            "notes": "tool_choice none must suppress generation grammar.",
        },
        {
            "name": "07-roundtrip-part1",
            "stream": False,
            "max_tokens": 512,
            "body": {
                "model": "__MODEL__",
                "temperature": TEMPERATURE,
                "seed": SEED,
                "max_tokens": 512,
                "stream": False,
                "tool_choice": {"type": "function", "function": {"name": "inspect_repository_state"}},
                "tools": catalog,
                "messages": [
                    {
                        "role": "user",
                        "content": "Inspect repository C:/git/g4-final-review at ref be410567f2b3f8146eda87087beb59b67199c893. "
                        "Include status and generated_artifacts scopes, read_only true, fail_on_dirty false.",
                    }
                ],
            },
            "expect": "one inspect_repository_state call; part2 feeds synthetic tool result",
            "notes": "Roundtrip part 1. Synthetic response used in part 2; no real tool executed.",
        },
        {
            "name": "08-streaming-nested",
            "stream": True,
            "max_tokens": 768,
            "body": {
                "model": "__MODEL__",
                "temperature": TEMPERATURE,
                "seed": SEED,
                "max_tokens": 768,
                "stream": True,
                "tool_choice": {"type": "function", "function": {"name": "run_runtime_acceptance"}},
                "tools": catalog,
                "messages": [{"role": "user", "content": named_nested_prompt}],
            },
            "expect": "SSE tool_call deltas reconstruct to one complete named call",
            "notes": "Streaming nested: reconstruct every indexed call, no filtering of empty/sparse indices.",
        },
        {
            "name": "09-low-token-truncation",
            "stream": False,
            "max_tokens": 16,
            "body": {
                "model": "__MODEL__",
                "temperature": TEMPERATURE,
                "seed": SEED,
                "max_tokens": 16,
                "stream": False,
                "tool_choice": "required",
                "tools": catalog,
                "messages": [{"role": "user", "content": named_nested_prompt}],
            },
            "expect": "likely finish_reason length or incomplete arguments; classified TRUNCATION",
            "notes": "Deliberate low-token run; failure here is expected truncation, not parser bug.",
        },
        {
            "name": "10-required-without-tools",
            "stream": False,
            "max_tokens": 256,
            "body": {
                "model": "__MODEL__",
                "temperature": TEMPERATURE,
                "seed": SEED,
                "max_tokens": 256,
                "stream": False,
                "tool_choice": "required",
                "messages": [{"role": "user", "content": "Say hello."}],
            },
            "expect": "4xx",
            "notes": "Negative control: required with no tools must fail closed.",
        },
        {
            "name": "11-named-without-tools",
            "stream": False,
            "max_tokens": 256,
            "body": {
                "model": "__MODEL__",
                "temperature": TEMPERATURE,
                "seed": SEED,
                "max_tokens": 256,
                "stream": False,
                "tool_choice": {"type": "function", "function": {"name": "inspect_repository_state"}},
                "messages": [{"role": "user", "content": "Say hello."}],
            },
            "expect": "4xx",
            "notes": "Negative control: named choice with no tools must fail closed.",
        },
        {
            "name": "12-parameterless",
            "stream": False,
            "max_tokens": 256,
            "body": {
                "model": "__MODEL__",
                "temperature": TEMPERATURE,
                "seed": SEED,
                "max_tokens": 256,
                "stream": False,
                "tool_choice": {"type": "function", "function": {"name": "get_server_time"}},
                "tools": [param_tool],
                "messages": [{"role": "user", "content": "What time is it on the server? Call get_server_time."}],
            },
            "expect": "get_server_time call with {} or empty arguments string",
            "notes": "Parameterless function wire contract.",
        },
        {
            "name": "13-literal-marker-in-string",
            "stream": False,
            "max_tokens": 512,
            "body": {
                "model": "__MODEL__",
                "temperature": TEMPERATURE,
                "seed": SEED,
                "max_tokens": 512,
                "stream": False,
                "tool_choice": {"type": "function", "function": {"name": "echo_marker"}},
                "tools": [echo_tool],
                "messages": [
                    {
                        "role": "user",
                        "content": "Call echo_marker with text exactly: a <tool_call|> b. "
                        "The marker text must stay inside the JSON string argument value.",
                    }
                ],
            },
            "expect": "arguments JSON parses, text field contains literal <tool_call|>, no leak outside argument strings",
            "notes": "Parser must not split on markers inside JSON strings.",
        },
    ]
    return cases


SYNTHETIC_TOOL_RESULT = {
    "status": "clean",
    "ref": "be410567f2b3f8146eda87087beb59b67199c893",
    "scopes": ["status", "generated_artifacts"],
    "read_only": True,
}


def analyze_nonstream(status, raw, body, catalog_names):
    out = {}
    out["http_status"] = status
    try:
        text = raw.decode("utf-8", errors="replace")
    except Exception:
        text = ""
    out["raw_len"] = len(raw)
    parsed = None
    parse_err = None
    try:
        parsed = json.loads(text) if text.strip() else None
    except Exception as e:
        parse_err = "%s: %s" % (type(e).__name__, e)
    out["response_json_parse_error"] = parse_err
    msg = None
    finish = None
    content = None
    tool_calls = []
    if isinstance(parsed, dict):
        try:
            ch = parsed.get("choices", [])[0]
            finish = ch.get("finish_reason")
            msg = ch.get("message", {})
            content = msg.get("content")
            tool_calls = msg.get("tool_calls", []) or []
        except Exception as e:
            out["choice_extract_error"] = "%s: %s" % (type(e).__name__, e)
    out["finish_reason"] = finish
    out["content"] = content
    out["content_markers"] = find_markers(content) if isinstance(content, str) else []
    calls = []
    for tc in tool_calls:
        try:
            fn = (tc.get("function") or {})
            arg_raw = fn.get("arguments", "")
            entry = {
                "id": tc.get("id"),
                "type": tc.get("type"),
                "name": fn.get("name"),
                "arguments_raw": arg_raw,
                "arguments_len": len(arg_raw) if isinstance(arg_raw, str) else None,
            }
            try:
                entry["arguments_parsed"] = json.loads(arg_raw) if isinstance(arg_raw, str) else None
                entry["arguments_parse_error"] = None
                ap = entry["arguments_parsed"]
                entry["arguments_is_object"] = isinstance(ap, dict)
                if isinstance(ap, str):
                    entry["markers_inside_parsed_string_values"] = find_markers(ap)
            except Exception as e:
                entry["arguments_parsed"] = None
                entry["arguments_parse_error"] = "%s: %s" % (type(e).__name__, e)
            entry["name_in_registry"] = entry["name"] in catalog_names
            calls.append(entry)
        except Exception as e:
            calls.append({"extract_error": "%s: %s" % (type(e).__name__, e)})
    out["tool_calls"] = calls
    out["tool_count"] = len(calls)
    out["tool_ids"] = [c.get("id") for c in calls if isinstance(c, dict) and c.get("id")]
    out["ids_unique"] = len(out["tool_ids"]) == len(set(out["tool_ids"])) if out["tool_ids"] else True
    out["leak_outside_arguments"] = bool(out["content_markers"])
    out["raw_marker_hits"] = find_markers(text)
    return out, parsed


def analyze_sse(status, raw, body):
    out = {}
    out["http_status"] = status
    try:
        text = raw.decode("utf-8", errors="replace")
    except Exception:
        text = ""
    out["raw_len"] = len(raw)
    lines = text.splitlines()
    data_lines = [l for l in lines if l.strip().startswith("data:")]
    out["sse_data_line_count"] = len(data_lines)
    out["sse_done"] = any(l.strip() == "data: [DONE]" for l in lines)
    chunks = []
    chunk_errors = []
    for l in data_lines:
        payload = l.strip()[len("data:"):].strip()
        if payload == "[DONE]":
            continue
        try:
            chunks.append(json.loads(payload))
        except Exception as e:
            chunk_errors.append("%s: %s | %.120s" % (type(e).__name__, e, payload))
    out["sse_chunks_parsed"] = len(chunks)
    out["sse_chunk_errors"] = chunk_errors
    per_index = {}
    content_parts = []
    finish_reasons = []
    for ch in chunks:
        try:
            choices = ch.get("choices", [])
            if not choices:
                continue
            c0 = choices[0]
            fr = c0.get("finish_reason")
            if fr is not None:
                finish_reasons.append(fr)
            delta = c0.get("delta", {}) or {}
            dc = delta.get("content")
            if isinstance(dc, str) and dc:
                content_parts.append(dc)
            for tc in delta.get("tool_calls", []) or []:
                idx = tc.get("index", 0)
                slot = per_index.setdefault(
                    idx, {"index": idx, "ids": [], "names": [], "arg_fragments": [], "chunk_count": 0}
                )
                slot["chunk_count"] += 1
                if tc.get("id"):
                    slot["ids"].append(tc.get("id"))
                fn = tc.get("function") or {}
                if fn.get("name"):
                    slot["names"].append(fn.get("name"))
                if isinstance(fn.get("arguments"), str):
                    slot["arg_fragments"].append(fn.get("arguments"))
        except Exception:
            continue
    recon = []
    indices = sorted(per_index.keys())
    # detect sparse gaps explicitly without filtering
    gaps = [i for i in range(min(indices) + 1, max(indices)) if indices and i not in per_index] if indices else []
    for idx in indices:
        slot = per_index[idx]
        arg_concat = "".join(slot["arg_fragments"])
        entry = {
            "index": idx,
            "chunk_count": slot["chunk_count"],
            "ids": slot["ids"],
            "names": slot["names"],
            "arguments_concat": arg_concat,
            "arguments_concat_len": len(arg_concat),
            "empty_call": (not slot["ids"] and not slot["names"] and not arg_concat),
        }
        try:
            entry["arguments_parsed"] = json.loads(arg_concat) if arg_concat.strip() else None
            entry["arguments_parse_error"] = None
        except Exception as e:
            entry["arguments_parsed"] = None
            entry["arguments_parse_error"] = "%s: %s" % (type(e).__name__, e) if arg_concat.strip() else "empty"
        recon.append(entry)
    out["sse_indices_observed"] = indices
    out["sse_sparse_gaps"] = gaps
    out["sse_reconstructed_calls"] = recon
    out["tool_count"] = len(recon)
    out["finish_reasons_seen"] = finish_reasons
    out["finish_reason"] = finish_reasons[-1] if finish_reasons else None
    out["content_reconstructed"] = "".join(content_parts)
    out["content_markers"] = find_markers(out["content_reconstructed"])
    out["leak_outside_arguments"] = bool(out["content_markers"])
    out["raw_marker_hits"] = find_markers(text)
    return out


def classify(case, status, analysis, elapsed, expect_4xx=False):
    if status == -1:
        return "BLOCKED", "HARNESS_ERROR", "connection/transport failure; see transport_error"
    if expect_4xx:
        if 400 <= status < 500:
            return "PASS", "GENERATION_CONTRACT", "negative control returned 4xx as required"
        return "FAIL", "GENERATION_CONTRACT", "negative control expected 4xx, got %s" % status
    if 500 <= status < 600:
        return "FAIL", "GPU_RUNTIME", "server 5xx"
    if status != 200:
        return "FAIL", "GENERATION_CONTRACT", "unexpected HTTP %s" % status
    if elapsed >= REQUEST_TIMEOUT_S - 1:
        return "FAIL", "GPU_RUNTIME", "request deadline reached"
    fr = analysis.get("finish_reason")
    tc = analysis.get("tool_count", 0)
    name = case["name"]
    if name == "09-low-token-truncation":
        if fr == "length":
            return "PASS", "TRUNCATION", "truncated as designed with low max_tokens"
        # incomplete arguments also counts as truncation evidence; record uncertainty
        bad_parse = False
        for c in analysis.get("tool_calls", []) or analysis.get("sse_reconstructed_calls", []):
            if isinstance(c, dict) and c.get("arguments_parse_error"):
                bad_parse = True
        if bad_parse:
            return "PASS", "TRUNCATION", "arguments incomplete under 16-token budget (uncertain: finish=%s)" % fr
        return "FAIL", "TRUNCATION", "expected truncation/length, got finish=%s" % fr
    # auto case: either plain text or valid tool calls are acceptable; wire contract must hold either way
    if name == "03-auto-tool":
        if tc == 0:
            if analysis.get("leak_outside_arguments"):
                return "FAIL", "PARSER", "markers in content in auto text path"
            content = analysis.get("content") or analysis.get("content_reconstructed") or ""
            if not (isinstance(content, str) and content.strip()):
                return "FAIL", "MODEL_QUALITY", "empty content in auto text path (uncertain)"
            return "PASS", "GENERATION_CONTRACT", "auto chose text; wire contract holds"
        for c in analysis.get("tool_calls", []) or analysis.get("sse_reconstructed_calls", []):
            if isinstance(c, dict) and c.get("arguments_parse_error"):
                return "FAIL", "PARSER", "auto tool arguments failed to parse as JSON"
        if analysis.get("leak_outside_arguments"):
            return "FAIL", "PARSER", "protocol markers leaked into content outside argument strings"
        return "PASS", "GENERATION_CONTRACT", "auto chose tool; wire contract holds (semantic choice uncertain)"
    if name in ("05-required-call", "04-named-nested", "12-parameterless", "13-literal-marker-in-string",
                 "07-roundtrip-part1", "07-roundtrip-part2", "08-streaming-nested"):
        if tc == 0:
            if fr == "length":
                return "FAIL", "TRUNCATION", "no calls; truncated"
            return "FAIL", "GENERATION_CONTRACT", "required/named choice produced zero tool calls (finish=%s)" % fr
        # check parse errors -> PARSER
        for c in analysis.get("tool_calls", []) or analysis.get("sse_reconstructed_calls", []):
            if isinstance(c, dict) and c.get("arguments_parse_error"):
                return "FAIL", "PARSER", "arguments failed to parse as JSON"
        if analysis.get("leak_outside_arguments"):
            return "FAIL", "PARSER", "protocol markers leaked into content outside argument strings"
        return "PASS", "GENERATION_CONTRACT", "wire contract holds (uncertain on semantic quality: see MODEL_QUALITY note)"
    # none case
    if name == "06-none":
        if tc != 0:
            return "FAIL", "GENERATION_CONTRACT", "tool_choice none but calls emitted"
        if analysis.get("leak_outside_arguments"):
            return "FAIL", "PARSER", "markers in content with choice none"
        return "PASS", "GENERATION_CONTRACT", "no calls as required"
    # text cases
    if tc != 0:
        return "FAIL", "GENERATION_CONTRACT", "unexpected tool calls in text-only case"
    if analysis.get("leak_outside_arguments"):
        return "FAIL", "PARSER", "markers leaked into text content"
    content = analysis.get("content") or analysis.get("content_reconstructed") or ""
    if not (isinstance(content, str) and content.strip()):
        return "FAIL", "MODEL_QUALITY", "empty content (wire ok, uncertain: model quality vs harness prompt)"
    return "PASS", "GENERATION_CONTRACT", "text contract holds"


def main():
    global REQUEST_TIMEOUT_S
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", required=True, choices=["A", "B"])
    ap.add_argument("--binary", required=True)
    ap.add_argument("--model-path", required=True)
    ap.add_argument("--model-name", required=True)
    ap.add_argument("--rest-port", type=int, required=True)
    ap.add_argument("--grpc-port", type=int, required=True)
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--evidence-dir", required=True)
    ap.add_argument("--session-id", default=None)
    ap.add_argument("--readiness-timeout", type=int, default=180)
    ap.add_argument("--request-timeout", type=int, default=180)
    args = ap.parse_args()

    REQUEST_TIMEOUT_S = args.request_timeout

    session_id = args.session_id or str(uuid.uuid4())
    ev_dir = os.path.abspath(args.evidence_dir)
    cases_dir = os.path.join(ev_dir, "cases")
    os.makedirs(cases_dir, exist_ok=True)

    with open(os.path.abspath(args.catalog), "r", encoding="utf-8") as f:
        catalog_doc = json.load(f)
    catalog_tools = catalog_doc.get("tools", [])
    catalog_names = [t["function"]["name"] for t in catalog_tools if "function" in t]
    catalog_names += ["get_server_time", "echo_marker"]

    manifest = {
        "session_id": session_id,
        "variant": args.variant,
        "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "binary": os.path.abspath(args.binary),
        "model_name": args.model_name,
        "model_path": os.path.abspath(args.model_path),
        "rest_port": args.rest_port,
        "grpc_port": args.grpc_port,
        "chat_path": CHAT_PATH,
        "temperature": TEMPERATURE,
        "seed": SEED,
        "request_timeout_s": args.request_timeout,
        "readiness_timeout_s": args.readiness_timeout,
    }
    # hashes (binary + model artifacts); record failure explicitly, never guess
    for label, p in [
        ("binary_sha256", manifest["binary"]),
        ("graph_sha256", os.path.join(manifest["model_path"], "graph.pbtxt")),
        ("template_sha256", os.path.join(manifest["model_path"], "chat_template.jinja")),
        ("tokenizer_config_sha256", os.path.join(manifest["model_path"], "tokenizer_config.json")),
    ]:
        try:
            manifest[label] = sha256_file(p)
            manifest[label + "_path"] = p
        except Exception as e:
            manifest[label] = "UNAVAILABLE: %s: %s" % (type(e).__name__, e)
            manifest[label + "_path"] = p
    try:
        manifest["catalog_sha256"] = sha256_file(os.path.abspath(args.catalog))
    except Exception as e:
        manifest["catalog_sha256"] = "UNAVAILABLE: %s" % e
    try:
        import subprocess as _sp
        manifest["git_head"] = _sp.check_output(
            ["git", "-C", r"C:\git\g4-final-review", "rev-parse", "HEAD"], text=True
        ).strip()
    except Exception as e:
        manifest["git_head"] = "UNAVAILABLE: %s" % e

    with open(os.path.join(ev_dir, "session.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    # pre-launch port check; never kill anything
    pre = {
        "rest_free": port_is_free(args.rest_port),
        "grpc_free": port_is_free(args.grpc_port),
    }
    if not (pre["rest_free"] and pre["grpc_free"]):
        with open(os.path.join(ev_dir, "BLOCKER.json"), "w", encoding="utf-8") as f:
            json.dump({"blocker": "ports not free before launch; refusing to kill existing processes",
                       "detail": pre, "manifest": manifest}, f, indent=2)
        print("BLOCKED: ports not free: %s" % pre)
        return 2

    server_log = os.path.join(ev_dir, "ovms_server.log")
    stdout_log = os.path.join(ev_dir, "server_stdout.log")
    stderr_log = os.path.join(ev_dir, "server_stderr.log")
    readiness_log = os.path.join(ev_dir, "readiness.log")

    env = dict(os.environ)
    env["PATH"] = ";".join(PATH_PREPEND) + ";" + env.get("PATH", "")
    env["PYTHONHOME"] = r"C:\opt\Python312"
    env["PYTHONPATH"] = r"C:\llm\ovms\python" + ";" + r"C:\opt\Python312\Lib\site-packages"

    cmd = [
        manifest["binary"],
        "--model_path", manifest["model_path"],
        "--model_name", args.model_name,
        "--rest_port", str(args.rest_port),
        "--port", str(args.grpc_port),
        "--log_level", "DEBUG",
        "--log_path", server_log,
    ]
    with open(os.path.join(ev_dir, "server_cmd.json"), "w", encoding="utf-8") as f:
        json.dump({"cmd": cmd, "env_PATH_prepend": PATH_PREPEND,
                   "PYTHONHOME": env["PYTHONHOME"], "PYTHONPATH": env["PYTHONPATH"]}, f, indent=2)

    creationflags = 0
    if os.name == "nt":
        creationflags = 0x08000000  # CREATE_NO_WINDOW: background helpers stay hidden

    fout = open(stdout_log, "wb")
    ferr = open(stderr_log, "wb")
    proc = subprocess.Popen(cmd, env=env, stdout=fout, stderr=ferr, creationflags=creationflags)
    manifest["child_pid"] = proc.pid
    print("launched pid=%s variant=%s session=%s" % (proc.pid, args.variant, session_id))

    readiness_entries = []
    base = "http://127.0.0.1:%d" % args.rest_port
    ready = False
    t0 = time.monotonic()
    try:
        while time.monotonic() - t0 < args.readiness_timeout:
            if proc.poll() is not None:
                readiness_entries.append({"t": round(time.monotonic() - t0, 1),
                                          "event": "child exited early code=%s" % proc.returncode})
                break
            for path in ["/v2/health/ready", "/v1/models", "/v3/models"]:
                st, body = http_get_raw(base + path, timeout=5)
                readiness_entries.append({"t": round(time.monotonic() - t0, 1), "path": path,
                                          "status": st, "bytes": len(body)})
                if st == 200 and (b"READY" in body or b"gemma" in body.lower() or b"model" in body.lower()):
                    # confirm model list mentions our model when available
                    ready = True
                    break
            if ready:
                break
            time.sleep(5)
        with open(readiness_log, "w", encoding="utf-8") as f:
            json.dump(readiness_entries, f, indent=2)
        if not ready:
            with open(os.path.join(ev_dir, "BLOCKER.json"), "w", encoding="utf-8") as f:
                json.dump({"blocker": "readiness deadline exceeded", "manifest": manifest,
                           "readiness_tail": readiness_entries[-10:]}, f, indent=2)
            print("BLOCKED: readiness deadline exceeded")
            return 3

        cases = build_cases(catalog_tools)
        # substitute model name
        for c in cases:
            c["body"]["model"] = args.model_name
        results = []
        roundtrip_part1_calls = None
        for c in cases:
            cdir = os.path.join(cases_dir, c["name"])
            os.makedirs(cdir, exist_ok=True)
            with open(os.path.join(cdir, "request.json"), "w", encoding="utf-8") as f:
                json.dump({"method": "POST", "url": base + CHAT_PATH, "body": c["body"]}, f, indent=2)
            t_start = time.monotonic()
            try:
                status, raw, elapsed, transport_err = http_json("POST", base + CHAT_PATH, c["body"],
                                                                timeout=args.request_timeout)
            except Exception as e:
                status, raw, elapsed, transport_err = -1, b"", 0, "%s: %s" % (type(e).__name__, e)
            with open(os.path.join(cdir, "response_raw.bin"), "wb") as f:
                f.write(raw)
            expect_4xx = c["name"] in ("10-required-without-tools", "11-named-without-tools")
            try:
                if c.get("stream"):
                    analysis, _ = analyze_sse(status, raw, c["body"]), None
                else:
                    analysis, _ = analyze_nonstream(status, raw, c["body"], catalog_names)
            except Exception as e:
                analysis = {"analysis_error": "%s: %s\n%s" % (type(e).__name__, e, traceback.format_exc())}
            analysis["elapsed_s"] = round(elapsed, 3)
            if transport_err:
                analysis["transport_error"] = transport_err
            verdict, fclass, reason = classify(c, status, analysis, elapsed, expect_4xx)
            if c["name"] == "07-roundtrip-part1" and verdict == "PASS":
                roundtrip_part1_calls = analysis.get("tool_calls")
            result = {"case": c["name"], "expect": c["expect"], "notes": c["notes"],
                      "max_tokens": c["max_tokens"], "stream": c["stream"],
                      "verdict": verdict, "failure_class": fclass, "reason": reason,
                      "uncertainty": "semantic intent (MODEL_QUALITY) recorded as uncertain; wire contract is authoritative",
                      "analysis": analysis}
            with open(os.path.join(cdir, "result.json"), "w", encoding="utf-8") as f:
                json.dump(result, f, indent=2)
            results.append({k: result[k] for k in ("case", "verdict", "failure_class", "reason")})
            print("%s -> %s [%s] %.1fs" % (c["name"], verdict, fclass, elapsed))

        # roundtrip part 2 with deterministic synthetic tool response
        cdir2 = os.path.join(cases_dir, "07-roundtrip-part2")
        os.makedirs(cdir2, exist_ok=True)
        part1 = None
        try:
            with open(os.path.join(cases_dir, "07-roundtrip-part1", "result.json"), encoding="utf-8") as f:
                part1 = json.load(f)
        except Exception as e:
            part1 = {"verdict": "BLOCKED", "reason": "no part1: %s" % e}
        if part1.get("verdict") == "PASS":
            tc0 = (part1["analysis"]["tool_calls"] or [{}])[0]
            call_id = tc0.get("id") or "call_synth_001"
            req2 = {
                "model": args.model_name,
                "temperature": TEMPERATURE,
                "seed": SEED,
                "max_tokens": 512,
                "stream": False,
                "tools": catalog_tools,
                "messages": [
                    {"role": "user", "content": "Inspect repository C:/git/g4-final-review at ref be410567; include status scope."},
                    {"role": "assistant", "content": None, "tool_calls": [
                        {"id": call_id, "type": "function",
                         "function": {"name": "inspect_repository_state",
                                      "arguments": tc0.get("arguments_raw", "{}")}}]},
                    {"role": "tool", "tool_call_id": call_id, "name": "inspect_repository_state",
                     "content": json.dumps(SYNTHETIC_TOOL_RESULT)},
                ],
            }
            case2 = {"name": "07-roundtrip-part2", "stream": False, "max_tokens": 512}
            with open(os.path.join(cdir2, "request.json"), "w", encoding="utf-8") as f:
                json.dump({"method": "POST", "url": base + CHAT_PATH, "body": req2}, f, indent=2)
            status, raw, elapsed, transport_err = http_json("POST", base + CHAT_PATH, req2,
                                                             timeout=args.request_timeout)
            with open(os.path.join(cdir2, "response_raw.bin"), "wb") as f:
                f.write(raw)
            analysis, _ = analyze_nonstream(status, raw, req2, catalog_names)
            analysis["elapsed_s"] = round(elapsed, 3)
            if transport_err:
                analysis["transport_error"] = transport_err
            # part2 passes if final text present and no leak; tool calls optional
            if status == 200 and not analysis.get("leak_outside_arguments"):
                content = analysis.get("content") or ""
                if isinstance(content, str) and content.strip():
                    verdict, fclass, reason = "PASS", "GENERATION_CONTRACT", "roundtrip summary returned with synthetic tool result"
                else:
                    verdict, fclass, reason = "FAIL", "MODEL_QUALITY", "empty summary after tool result (uncertain)"
            else:
                verdict, fclass, reason = classify(case2, status, analysis, elapsed, False)
            result2 = {"case": "07-roundtrip-part2",
                       "expect": "final summary grounded in synthetic tool result; no re-emitted markers",
                       "notes": "Deterministic synthetic tool response; no real tool executed.",
                       "max_tokens": 512, "stream": False, "verdict": verdict,
                       "failure_class": fclass, "reason": reason,
                       "uncertainty": "grounding quality is MODEL_QUALITY/uncertain; wire contract authoritative",
                       "analysis": analysis}
            with open(os.path.join(cdir2, "result.json"), "w", encoding="utf-8") as f:
                json.dump(result2, f, indent=2)
            results.append({k: result2[k] for k in ("case", "verdict", "failure_class", "reason")})
            print("07-roundtrip-part2 -> %s [%s] %.1fs" % (verdict, fclass, elapsed))
        else:
            with open(os.path.join(cdir2, "result.json"), "w", encoding="utf-8") as f:
                json.dump({"case": "07-roundtrip-part2", "verdict": "BLOCKED",
                           "failure_class": "HARNESS_ERROR",
                           "reason": "part1 did not pass; part2 not attempted",
                           "part1": {k: part1.get(k) for k in ("verdict", "failure_class", "reason")}}, f, indent=2)
            results.append({"case": "07-roundtrip-part2", "verdict": "BLOCKED",
                            "failure_class": "HARNESS_ERROR", "reason": "part1 not PASS"})
        manifest["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        manifest["results"] = results
        with open(os.path.join(ev_dir, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2)
        return 0
    finally:
        try:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=30)
                except Exception:
                    proc.kill()
        except Exception:
            pass
        try:
            fout.close()
        except Exception:
            pass
        try:
            ferr.close()
        except Exception:
            pass
        time.sleep(3)
        manifest["ports_released"] = {"rest_free": port_is_free(args.rest_port),
                                      "grpc_free": port_is_free(args.grpc_port)}
        try:
            with open(os.path.join(ev_dir, "manifest.json"), "w", encoding="utf-8") as f:
                json.dump(manifest, f, indent=2)
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())
