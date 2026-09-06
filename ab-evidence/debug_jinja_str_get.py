# Temporary debug reproducer for LLMExecutor "'str' object has no attribute 'get'".
# Mirrors OVMS ImmutableSandboxedEnvironment + saved request2 payload.
import json
import time
import traceback
from copy import deepcopy
from pathlib import Path

LOG = Path(r"C:\git\model_server-gemma4-clean\debug-afec93.log")
REQ = Path(r"C:\git\model_server-gemma4-google-template-session-state\ab-evidence\newest-runtime\live-named-seed42\request2-input.json")
TMPL = Path(r"C:\llm\models\runtime\gemma4-26-heretic-google-current\chat_template.jinja")


def agent_log(hypothesis_id, message, data):
    rec = {
        "sessionId": "afec93",
        "hypothesisId": hypothesis_id,
        "location": "debug_jinja_str_get.py",
        "message": message,
        "data": data,
        "timestamp": int(time.time() * 1000),
        "runId": "pre-fix",
    }
    with LOG.open("a", encoding="utf-8") as f:
        f.write(json.dumps(rec, default=str) + "\n")


def shapes(messages):
    out = []
    for i, m in enumerate(messages if isinstance(messages, list) else []):
        if not isinstance(m, dict):
            out.append({"i": i, "type": type(m).__name__, "preview": str(m)[:80]})
            continue
        tc = m.get("tool_calls")
        fn_args_t = None
        tc0_t = None
        if isinstance(tc, list) and tc:
            tc0_t = type(tc[0]).__name__
            if isinstance(tc[0], dict):
                fn = tc[0].get("function")
                if isinstance(fn, dict):
                    fn_args_t = type(fn.get("arguments")).__name__
        out.append({
            "i": i,
            "type": type(m).__name__,
            "role": m.get("role"),
            "content_type": type(m.get("content")).__name__,
            "tool_calls_type": type(tc).__name__,
            "tool_calls0_type": tc0_t,
            "arguments_type": fn_args_t,
        })
    return out


def parse_args_objects(messages):
    cloned = deepcopy(messages)
    for m in cloned:
        for tc in m.get("tool_calls") or []:
            if not isinstance(tc, dict):
                continue
            fn = tc.get("function") or {}
            args = fn.get("arguments")
            if isinstance(args, str):
                fn["arguments"] = json.loads(args)
        if m.get("role") == "tool" and isinstance(m.get("content"), str):
            try:
                parsed = json.loads(m["content"])
                if isinstance(parsed, dict):
                    m["content"] = parsed
            except Exception:
                pass
    return cloned


def render(template, messages, tools, label, hypothesis_id):
    try:
        out = template.render(
            messages=messages,
            tools=tools,
            bos_token="<bos>",
            eos_token="<eos>",
            add_generation_prompt=True,
        )
        agent_log(hypothesis_id, f"{label} render ok", {"n_chars": len(out), "head": out[:180]})
        print(f"{label}: OK {len(out)} chars")
    except Exception as e:
        tb = traceback.format_exc()
        agent_log(hypothesis_id, f"{label} render exception", {"error": str(e), "traceback": tb[-4000:]})
        print(f"{label}: FAIL {e}")
        print(tb[-1500:])


def main():
    import jinja2
    from jinja2.sandbox import ImmutableSandboxedEnvironment

    def raise_exception(message):
        raise jinja2.exceptions.TemplateError(message)

    src = TMPL.read_text(encoding="utf-8")
    req = json.loads(REQ.read_text(encoding="utf-8"))
    messages = req["messages"]
    tools = req.get("tools")

    agent_log("A-B-C-D", "pre-render message/tool shapes", {
        "n_messages": len(messages),
        "messages_type": type(messages).__name__,
        "tools_type": type(tools).__name__,
        "tools0_type": type(tools[0]).__name__ if tools else None,
        "shapes": shapes(messages),
        "has_response_is_mapping": "response is mapping" in src,
        "has_arguments_is_mapping": "arguments'] is mapping" in src or 'arguments"] is mapping' in src,
    })

    env = ImmutableSandboxedEnvironment(trim_blocks=True, lstrip_blocks=True)
    env.globals["raise_exception"] = raise_exception
    env.filters["from_json"] = json.loads
    env.filters["tojson"] = lambda value, indent=None: json.dumps(value, ensure_ascii=False, indent=indent)
    template = env.from_string(src)

    render(template, messages, tools, "raw_http_request2", "B")
    render(template, parse_args_objects(messages), tools, "args_and_tool_content_as_objects", "C-D")

    only_args = deepcopy(messages)
    for m in only_args:
        for tc in m.get("tool_calls") or []:
            fn = (tc or {}).get("function") or {}
            if isinstance(fn.get("arguments"), str):
                fn["arguments"] = json.loads(fn["arguments"])
    render(template, only_args, tools, "args_objects_content_string", "C")


if __name__ == "__main__":
    main()
