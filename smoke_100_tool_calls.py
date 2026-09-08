import requests
import json
import time
import sys
from datetime import datetime

BASE = "http://localhost:8888"
MODEL = "gemma4"

# Tool schema for the "question" function
tools = [{
    "type": "function",
    "function": {
        "name": "question",
        "description": "Ask a question with options",
        "parameters": {
            "type": "object",
            "properties": {
                "questions": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "question": {"type": "string"},
                            "header": {"type": "string"},
                            "options": {
                                "type": "array",
                                "items": {
                                    "type": "object",
                                    "properties": {
                                        "label": {"type": "string"},
                                        "description": {"type": "string"}
                                    },
                                    "required": ["label", "description"]
                                }
                            },
                            "multiple": {"type": "boolean"},
                            "custom": {"type": "boolean"}
                        },
                        "required": ["question", "header", "options"]
                    }
                }
            },
            "required": ["questions"]
        }
    }
}]

payload_base = {
    "model": MODEL,
    "messages": [{"role": "user", "content": "Ask me a question"}],
    "tools": tools,
    "tool_choice": "auto",
    "max_tokens": 512,
    "temperature": 0.7
}

results = []

for i in range(100):
    try:
        start = time.perf_counter()
        resp = requests.post(f"{BASE}/v1/chat/completions", json=payload_base, timeout=60)
        elapsed = time.perf_counter() - start
        
        if resp.status_code != 200:
            results.append({"idx": i, "ok": False, "status": resp.status_code, "error": resp.text[:200]})
            continue
            
        data = resp.json()
        
        # Extract metrics
        usage = data.get("usage", {})
        prompt_tokens = usage.get("prompt_tokens", 0)
        completion_tokens = usage.get("completion_tokens", 0)
        total_tokens = usage.get("total_tokens", 0)
        
        # Check for tool calls
        choices = data.get("choices", [])
        tool_calls = []
        content = ""
        if choices:
            msg = choices[0].get("message", {})
            content = msg.get("content", "")
            tool_calls = msg.get("tool_calls", [])
        
        results.append({
            "idx": i,
            "ok": True,
            "latency_s": round(elapsed, 3),
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": total_tokens,
            "tool_calls": len(tool_calls),
            "content_preview": content[:120] if content else ""
        })
        
        if i % 10 == 0:
            print(f"[{i}/100] latency={elapsed:.2f}s tokens={total_tokens} tools={len(tool_calls)}")
            
    except Exception as e:
        results.append({"idx": i, "ok": False, "error": str(e)})

# Summary
ok_results = [r for r in results if r.get("ok")]
latencies = [r["latency_s"] for r in ok_results]
tokens = [r["completion_tokens"] for r in ok_results]
tools = [r["tool_calls"] for r in ok_results]

print("\n=== SMOKE TEST SUMMARY ===")
print(f"Total: {len(results)} | Success: {len(ok_results)} | Failed: {len(results)-len(ok_results)}")
if latencies:
    print(f"Latency: avg={sum(latencies)/len(latencies):.2f}s min={min(latencies):.2f}s max={max(latencies):.2f}s")
if tokens:
    print(f"Completion tokens: avg={sum(tokens)/len(tokens):.1f} min={min(tokens)} max={max(tokens)}")
if tools:
    print(f"Tool calls: avg={sum(tools)/len(tools):.1f} min={min(tools)} max={max(tools)}")

# Save detailed results
with open("smoke_100_results.json", "w") as f:
    json.dump({
        "timestamp": datetime.now().isoformat(),
        "model": MODEL,
        "total_calls": len(results),
        "successful": len(ok_results),
        "summary": {
            "avg_latency_s": round(sum(latencies)/len(latencies), 3) if latencies else 0,
            "avg_completion_tokens": round(sum(tokens)/len(tokens), 1) if tokens else 0,
            "avg_tool_calls": round(sum(tools)/len(tools), 1) if tools else 0
        },
        "details": results
    }, f, indent=2)

print("Results saved to smoke_100_results.json")