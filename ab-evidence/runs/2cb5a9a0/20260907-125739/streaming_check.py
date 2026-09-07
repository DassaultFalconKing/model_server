#!/usr/bin/env python3
import json
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = "http://127.0.0.1:18000/v3/chat/completions"
OUT = Path(__file__).resolve().parent / "streaming"
OUT.mkdir(parents=True, exist_ok=True)

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "inspect_build_state",
            "description": "Inspect build state",
            "parameters": {
                "type": "object",
                "properties": {"repo_path": {"type": "string"}},
                "required": ["repo_path"],
            },
        },
    }
]


def post(body, stream=False):
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        BASE, data=data, headers={"Content-Type": "application/json"}, method="POST"
    )
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            raw = resp.read()
            status = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read()
        status = e.code
    elapsed = time.monotonic() - t0
    text = raw.decode("utf-8", "replace")
    if stream:
        content = ""
        tool_calls = {}
        finish = None
        for line in text.splitlines():
            if not line.startswith("data: "):
                continue
            payload = line[6:].strip()
            if payload == "[DONE]":
                break
            try:
                chunk = json.loads(payload)
            except Exception:
                continue
            ch = (chunk.get("choices") or [{}])[0]
            delta = ch.get("delta") or {}
            if delta.get("content"):
                content += delta["content"]
            for tc in delta.get("tool_calls") or []:
                idx = tc.get("index", 0)
                slot = tool_calls.setdefault(
                    idx,
                    {
                        "id": None,
                        "type": "function",
                        "function": {"name": "", "arguments": ""},
                    },
                )
                if tc.get("id"):
                    slot["id"] = tc["id"]
                fn = tc.get("function") or {}
                if fn.get("name"):
                    slot["function"]["name"] += fn["name"]
                if fn.get("arguments"):
                    slot["function"]["arguments"] += fn["arguments"]
            if ch.get("finish_reason"):
                finish = ch["finish_reason"]
        calls = [tool_calls[i] for i in sorted(tool_calls)]
        return (
            status,
            {
                "assembled": {
                    "content": content,
                    "tool_calls": calls,
                    "finish_reason": finish,
                },
                "raw_preview": text[:2000],
            },
            elapsed,
        )
    return status, json.loads(text), elapsed


def extract(resp):
    if "assembled" in resp:
        a = resp["assembled"]
        return a.get("tool_calls") or [], a.get("finish_reason"), a.get("content") or ""
    ch = (resp.get("choices") or [{}])[0]
    msg = ch.get("message") or {}
    return msg.get("tool_calls") or [], ch.get("finish_reason"), msg.get("content") or ""


def main():
    results = []
    for mode, tc in [
        ("auto", "auto"),
        ("named", {"type": "function", "function": {"name": "inspect_build_state"}}),
        ("required", "required"),
    ]:
        body = {
            "model": "gemma4-26-heretic",
            "messages": [
                {
                    "role": "user",
                    "content": "Call inspect_build_state with repo_path='C:/git/model_server-gemma4-google-template-session-state'.",
                }
            ],
            "tools": TOOLS,
            "tool_choice": tc,
            "temperature": 0,
            "seed": 42,
            "max_tokens": 256,
        }
        s1, r1, e1 = post(dict(body, stream=False), stream=False)
        c1, f1, _ = extract(r1)
        s2, r2, e2 = post(dict(body, stream=True), stream=True)
        c2, f2, _ = extract(r2)
        name1 = (c1[0].get("function") or {}).get("name") if c1 else None
        name2 = (c2[0].get("function") or {}).get("name") if c2 else None
        args1 = (c1[0].get("function") or {}).get("arguments") if c1 else None
        args2 = (c2[0].get("function") or {}).get("arguments") if c2 else None
        eq = len(c1) == len(c2) and name1 == name2 and f1 == f2
        try:
            if args1 is not None and args2 is not None:
                eq = eq and (json.loads(args1) == json.loads(args2))
        except Exception:
            eq = False
        row = {
            "mode": mode,
            "http_ns": s1,
            "http_s": s2,
            "finish_ns": f1,
            "finish_s": f2,
            "count_ns": len(c1),
            "count_s": len(c2),
            "name_ns": name1,
            "name_s": name2,
            "equiv": eq,
            "elapsed_ns": round(e1, 3),
            "elapsed_s": round(e2, 3),
        }
        results.append(row)
        (OUT / f"{mode}-nonstream.json").write_text(
            json.dumps({"status": s1, "body": r1}, indent=2), encoding="utf-8"
        )
        (OUT / f"{mode}-stream.json").write_text(
            json.dumps({"status": s2, "body": r2}, indent=2), encoding="utf-8"
        )
        print(mode, row, flush=True)
    (OUT / "streaming-summary.json").write_text(
        json.dumps(results, indent=2), encoding="utf-8"
    )
    print("STREAMING_ALL_EQUIV", all(r["equiv"] for r in results), flush=True)
    return 0 if all(r["equiv"] and r["http_ns"] == 200 and r["http_s"] == 200 for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
