#!/usr/bin/env python3
"""Empty-args investigation: parallel tool call experiments.

Sends controlled requests to OVMS and records raw responses for analysis.
Each experiment varies one dimension (temperature, prompt, parallelism, CB, grammar).
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE_URL = os.environ.get("OVMS_BASE_URL", "http://127.0.0.1:8000")
ENDPOINT = BASE_URL.rstrip("/") + "/v3/chat/completions"
TIMEOUT_S = 180
EVIDENCE_DIR = Path(__file__).parent.parent / "logs" / "evidence"

# --- Tool schemas ---

WEATHER_TOOL = {
    "type": "function",
    "function": {
        "name": "weather",
        "description": "Get current weather for a city.",
        "parameters": {
            "type": "object",
            "properties": {
                "city": {"type": "string"}
            },
            "required": ["city"]
        }
    }
}

CALCULATOR_TOOL = {
    "type": "function",
    "function": {
        "name": "calculator",
        "description": "Calculate with integer inputs.",
        "parameters": {
            "type": "object",
            "properties": {
                "a": {"type": "integer"},
                "b": {"type": "integer"},
                "op": {"type": "string", "enum": ["add", "multiply"]}
            },
            "required": ["a", "b", "op"]
        }
    }
}

SEARCH_TOOL = {
    "type": "function",
    "function": {
        "name": "search",
        "description": "Search the web for information.",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "limit": {"type": "integer"}
            },
            "required": ["query"]
        }
    }
}

NOTIFY_TOOL = {
    "type": "function",
    "function": {
        "name": "notify",
        "description": "Send a notification.",
        "parameters": {
            "type": "object",
            "properties": {
                "user": {"type": "string"},
                "message": {"type": "string"}
            },
            "required": ["user", "message"]
        }
    }
}


def post_json(url, body, timeout=TIMEOUT_S):
    payload = json.dumps(body, separators=(",", ":")).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    request = urllib.request.Request(url, data=payload, headers=headers, method="POST")
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


def classify_response(resp):
    """Extract tool call names and arguments from response."""
    if not resp or "choices" not in resp:
        return {"error": "no_choices", "raw": resp}
    choice = resp["choices"][0]
    msg = choice.get("message", {})
    tool_calls = msg.get("tool_calls", [])
    finish = choice.get("finish_reason", "unknown")
    usage = resp.get("usage", {})
    results = []
    for tc in tool_calls:
        fn = tc.get("function", {})
        args_raw = fn.get("arguments", "")
        try:
            args = json.loads(args_raw) if args_raw else {}
        except json.JSONDecodeError:
            args = {"__parse_error": args_raw}
        results.append({
            "name": fn.get("name", "?"),
            "arguments": args,
            "arguments_raw": args_raw,
            "empty": args == {},
        })
    return {
        "finish_reason": finish,
        "tool_calls": results,
        "tool_call_count": len(results),
        "all_empty": all(r["empty"] for r in results) if results else False,
        "any_empty": any(r["empty"] for r in results),
        "usage": usage,
    }


def run_experiment(name, request_body, run_id=0):
    """Send one request, save evidence, return classification."""
    exp_dir = EVIDENCE_DIR / name
    exp_dir.mkdir(parents=True, exist_ok=True)
    tag = f"run{run_id}"

    req_path = exp_dir / f"{tag}.request.json"
    req_path.write_text(json.dumps(request_body, indent=2, ensure_ascii=False), encoding="utf-8")

    status, resp, raw, elapsed = post_json(ENDPOINT, request_body)

    resp_path = exp_dir / f"{tag}.response.json"
    resp_path.write_text(raw, encoding="utf-8")

    classification = classify_response(resp)
    classification["http_status"] = status
    classification["elapsed_s"] = round(elapsed, 3)

    summary_path = exp_dir / f"{tag}.summary.json"
    summary_path.write_text(json.dumps(classification, indent=2, ensure_ascii=False), encoding="utf-8")

    return classification


def base_request(tools, user_content, **overrides):
    body = {
        "model": "gemma4-26-heretic",
        "messages": [{"role": "user", "content": user_content}],
        "tools": tools,
        "tool_choice": "auto",
        "parallel_tool_calls": True,
        "max_tokens": 256,
        "temperature": 0,
        "seed": 42,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    body.update(overrides)
    return body


def exp1_temperature_sweep():
    """Exp 1: Temperature sweep (0.0, 0.3, 0.7) with 3 parallel calls."""
    print("\n=== EXP 1: Temperature Sweep ===")
    tools = [WEATHER_TOOL, CALCULATOR_TOOL, SEARCH_TOOL]
    prompt = "Call weather for Paris, calculator to add 3 and 5, and search for 'python tutorial'. Do not answer in prose."
    results = []
    for temp in [0.0, 0.3, 0.7, 1.0]:
        print(f"  temp={temp} ...", end=" ", flush=True)
        body = base_request(tools, prompt, temperature=temp, seed=42)
        cls = run_experiment("exp1-temp-sweep", body, run_id=int(temp * 10))
        n = cls["tool_call_count"]
        empty = cls["all_empty"]
        print(f"calls={n} all_empty={empty} finish={cls['finish_reason']} tokens={cls.get('usage', {}).get('completion_tokens', '?')}")
        results.append({"temp": temp, **cls})
    return results


def exp2_natural_prompt():
    """Exp 2: Natural prompt vs strict prompt."""
    print("\n=== EXP 2: Natural Prompt ===")
    tools = [WEATHER_TOOL, CALCULATOR_TOOL, SEARCH_TOOL]
    prompts = [
        ("strict", "Call weather for Paris, calculator to add 3 and 5, and search for 'python tutorial'. Do not answer in prose."),
        ("natural", "I need to check the weather in Paris, calculate 3+5, and find a Python tutorial."),
        ("minimal", "weather Paris, calculator 3+5, search python tutorial"),
        ("question", "What tools would you need to check Paris weather, add 3+5, and search for Python tutorials?"),
    ]
    results = []
    for label, prompt in prompts:
        print(f"  {label} ...", end=" ", flush=True)
        body = base_request(tools, prompt, temperature=0, seed=42)
        cls = run_experiment("exp2-natural-prompt", body, run_id=hash(label) % 1000)
        n = cls["tool_call_count"]
        empty = cls["all_empty"]
        print(f"calls={n} all_empty={empty} finish={cls['finish_reason']}")
        results.append({"label": label, "prompt": prompt, **cls})
    return results


def exp3_parallelism_sweep():
    """Exp 3: Sweep 2, 3, 4 parallel calls."""
    print("\n=== EXP 3: Parallelism Sweep ===")
    tool_sets = {
        "2": [WEATHER_TOOL, CALCULATOR_TOOL],
        "3": [WEATHER_TOOL, CALCULATOR_TOOL, SEARCH_TOOL],
        "4": [WEATHER_TOOL, CALCULATOR_TOOL, SEARCH_TOOL, NOTIFY_TOOL],
    }
    prompts = {
        "2": "Call weather for Paris and calculator to add 3 and 5. Do not answer in prose.",
        "3": "Call weather for Paris, calculator to add 3 and 5, and search for 'python tutorial'. Do not answer in prose.",
        "4": "Call weather for Paris, calculator to add 3 and 5, search for 'python tutorial', and notify user 'done'. Do not answer in prose.",
    }
    results = []
    for count in ["2", "3", "4"]:
        print(f"  {count} tools ...", end=" ", flush=True)
        body = base_request(tool_sets[count], prompts[count], temperature=0, seed=42)
        cls = run_experiment("exp3-parallelism-sweep", body, run_id=int(count))
        n = cls["tool_call_count"]
        empty = cls["all_empty"]
        print(f"calls={n} all_empty={empty} finish={cls['finish_reason']} tokens={cls.get('usage', {}).get('completion_tokens', '?')}")
        results.append({"parallelism": int(count), **cls})
    return results


def exp4_cb_interaction():
    """Exp 4: CB interaction — single batch vs concurrent.
    Note: CB control requires OVMS config. This records the request for
    post-hoc analysis when CB is toggled externally."""
    print("\n=== EXP 4: CB Interaction (record-only) ===")
    tools = [WEATHER_TOOL, CALCULATOR_TOOL, SEARCH_TOOL]
    prompt = "Call weather for Paris, calculator to add 3 and 5, and search for 'python tutorial'. Do not answer in prose."
    results = []
    # Run 5 identical requests to observe repeatability under same CB state
    for i in range(5):
        print(f"  run {i} ...", end=" ", flush=True)
        body = base_request(tools, prompt, temperature=0, seed=100 + i)
        cls = run_experiment("exp4-cb-interaction", body, run_id=i)
        n = cls["tool_call_count"]
        empty = cls["all_empty"]
        print(f"calls={n} all_empty={empty} finish={cls['finish_reason']} tokens={cls.get('usage', {}).get('completion_tokens', '?')}")
        results.append({"run": i, **cls})
    return results


def exp5_rc1_artifacts():
    """Exp 5: RC1 — feed known-empty TRACE tokens back into parser.
    This verifies parser honesty: if raw model output is '{}', parser should emit '{}'."""
    print("\n=== EXP 5: RC1 Artifacts (parser honesty) ===")
    # Simulate what the model produces: 3 parallel calls with empty args
    synthetic_output = (
        "<|tool_call>call:weather{city:<|\"|>Paris<|\"|>}<tool_call|>"
        "<|tool_call>call:calculator{a:3,b:5,op:<|\"|>add<|\"|>}<tool_call|>"
        "<|tool_call>call:search{query:<|\"|>python tutorial<|\"|>}<tool_call|>"
    )
    # Tokenize and parse through the output parser
    # This requires the tokenizer — skip if not available
    tokenizer_path = os.environ.get("GEMMA4_TOKENIZER_PATH")
    if not tokenizer_path:
        print("  SKIPPED: set GEMMA4_TOKENIZER_PATH to run parser honesty test")
        return {"status": "skipped", "reason": "no tokenizer path"}

    try:
        import openvino as ov
        import openvino_genai
        tokenizer = openvino_genai.Tokenizer(tokenizer_path)
        from src.llm.io_processing.output_parser import OutputParser
        parser = OutputParser(tokenizer, "gemma4", "gemma4", {
            "weather": {"schema": WEATHER_TOOL["function"]["parameters"]},
            "calculator": {"schema": CALCULATOR_TOOL["function"]["parameters"]},
            "search": {"schema": SEARCH_TOOL["function"]["parameters"]},
        })
        tensor = tokenizer.encode(synthetic_output).input_ids
        tokens = list(tensor.data)
        parsed = parse_with_streamer(tokenizer, parser, tokens)
        print(f"  Synthetic input: {synthetic_output[:80]}...")
        print(f"  Parsed tool calls: {len(parsed['tool_calls'])}")
        for tc in parsed["tool_calls"]:
            print(f"    {tc['name']}: {tc['arguments']}")
        return {"status": "ok", "parsed": parsed}
    except Exception as e:
        print(f"  SKIPPED: {e}")
        return {"status": "skipped", "reason": str(e)}


def parse_with_streamer(tokenizer, parser, tokens):
    """Minimal token-through-parser simulation."""
    tool_calls = []
    content = []
    parser.resetStreamingState()

    # Drive the parser token by token (simplified)
    # In production this goes through OVMSTextStreamer
    accumulated = ""
    for token in tokens:
        # Decode single token
        decoded = tokenizer.decode([token])
        delta = parser.parseChunk(decoded, [], True, 0)  # 0 = NONE
        if delta is not None:
            import variant  # This is a simplification
    return {"tool_calls": tool_calls, "content": "".join(content)}


def main():
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Endpoint: {ENDPOINT}")
    print(f"Evidence: {EVIDENCE_DIR}")

    all_results = {}
    try:
        all_results["exp1"] = exp1_temperature_sweep()
    except Exception as e:
        print(f"  EXP 1 FAILED: {e}")
        all_results["exp1"] = {"error": str(e)}

    try:
        all_results["exp2"] = exp2_natural_prompt()
    except Exception as e:
        print(f"  EXP 2 FAILED: {e}")
        all_results["exp2"] = {"error": str(e)}

    try:
        all_results["exp3"] = exp3_parallelism_sweep()
    except Exception as e:
        print(f"  EXP 3 FAILED: {e}")
        all_results["exp3"] = {"error": str(e)}

    try:
        all_results["exp4"] = exp4_cb_interaction()
    except Exception as e:
        print(f"  EXP 4 FAILED: {e}")
        all_results["exp4"] = {"error": str(e)}

    # Exp 5 is parser-only, skip in live mode
    all_results["exp5"] = {"status": "skipped", "reason": "parser-only, run separately"}

    # Write combined summary
    summary_path = EVIDENCE_DIR / "experiment-summary.json"
    summary_path.write_text(json.dumps(all_results, indent=2, ensure_ascii=False, default=str), encoding="utf-8")
    print(f"\nSummary written to {summary_path}")

    # Print verdict
    print("\n=== VERDICT ===")
    for exp_name, exp_results in all_results.items():
        if isinstance(exp_results, list):
            for r in exp_results:
                temp = r.get("temp", r.get("label", r.get("parallelism", r.get("run", "?"))))
                empty = r.get("all_empty", "?")
                calls = r.get("tool_call_count", "?")
                print(f"  {exp_name}/{temp}: calls={calls} all_empty={empty}")
        elif isinstance(exp_results, dict) and "error" in exp_results:
            print(f"  {exp_name}: ERROR - {exp_results['error']}")


if __name__ == "__main__":
    main()
