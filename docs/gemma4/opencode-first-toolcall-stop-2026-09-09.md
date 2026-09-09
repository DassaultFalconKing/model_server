# Root cause: OpenCode stops after the first tool call (2026-09-09)

Status: **closed for the OpenCode client path**. Not a Jinja overlay regression.
This is an evidence note for the live 2026.5 candidate, not a production OVMS patch.

## Identity under test

| Item | Value |
|---|---|
| Worktree | `C:\git\model_server-gemma4-fast` |
| Branch | `integration/ovms-2026.5-forward-port` |
| HEAD | `2d17e36f39412f18df558c49c6bc4661b833f675` |
| Binary | `C:\git\model_server-gemma4-fast\bazel-bin\src\ovms.exe` |
| Process | `ovms.exe` PID 27736, started 2026-09-09 04:43:59 local |
| REST / gRPC | `127.0.0.1:8000` / `9000` |
| Runtime dir | `tmp\gemmamonster-ovms\2026.5-candidate-e` |
| Profile | E (`max_num_seqs: 1`, `KV_CACHE_PRECISION: u8`, prefix caching on, `cache_size` unpinned) |
| Overlay | `C:\llm\models\OpenVINO\gemma4-google-template-overlay` |
| Model id | `gemma4-26-heretic` |
| Chat template | `JINJA` (`chat_template_mode: JINJA` in generated `graph.pbtxt`) |
| Graph queue | disabled (`graph_queue_size=0`) |
| Session store | unset (`OVMS_SESSION_STORE_DIR` empty; OpenCode does not send `X-OVMS-Session-ID`) |
| Client | OpenCode 1.18.29, `@ai-sdk/openai-compatible`, `POST /v3/chat/completions` stream |

Launch that matches the live process:

```powershell
pwsh -File .\scripts\gemma4\launch-gemma4-candidate.ps1 `
  -OvmsExe '.\bazel-bin\src\ovms.exe' `
  -ModelPath 'C:\llm\models\OpenVINO\gemma4-google-template-overlay' `
  -ModelName 'gemma4-26-heretic' `
  -ShortRoot g5 `
  -Profile E `
  -ChatTemplateMode JINJA
```

## Symptom

OpenCode TUI / `opencode run` appeared to die after the first tool call or the first assistant answer.

It was not a hang. The agent loop **exited cleanly** after a second LLM turn that returned no tools and no usable text.

Observed session `ses_f7bd2dd86ffeusQPAtKWDSPmRD` (`/init`, agent `build`):

| Time (local) | Event |
|---|---|
| 05:19:05 | Title stream starts (`small=true`, same model, same GPU) |
| 05:19:07 | Main `/init` stream starts while title is still in flight |
| 05:19:14 | OVMS `All requests: 2; Scheduled requests: 2` with prefix cache ~14% |
| 05:19:37 | First tool call `glob` `AGENTS.md`; `finish_reason=tool_calls`; 19 completion tokens |
| 05:19:39 | Request2 (assistant `tool_calls` + `role=tool` result `"No files found"`) |
| 05:19:40 | Request2 complete: `finish_reason=stop`, **4 completion tokens**, empty `content`, no `tool_calls` |
| 05:19:41 | OpenCode `exiting loop` at step 2 |
| 05:20:25 | User follow-up; 22 tokens of `?` then `AGENTS.md`; loop exits again |

OpenCode sent `max_tokens: 16384`, `tool_choice: auto`, **no `temperature`**, **no `seed`**, **no `chat_template_kwargs`**. OVMS then logged `Randomizing rng_seed for multinomial sampling`.

ChatTemplateProcessor on request2 succeeded (no HTTP 400, no `'str' object has no attribute 'get'`).

## What this is not

### Not a Jinja overlay regression

The Google-template generation tail in the overlay is:

```jinja
{%- if add_generation_prompt -%}
    {%- if ns.prev_message_type != 'tool_response' and ns.prev_message_type != 'tool_call' -%}
        {{- '<|turn>model\n' -}}
        {%- if not enable_thinking -%}
            {{- '<|channel>thought\n<channel|>' -}}
        {%- endif -%}
    {%- elif ns.prev_message_type == 'tool_response' and enable_thinking -%}
        {{- '<|channel>thought\n' -}}
    {%- endif -%}
{%- endif -%}
```

After a tool result, `enable_thinking` defaults to `false`, so the template does **not** emit a new `<|turn>model>`. That is the Google same-turn continuation protocol: the assistant turn is left open (`<turn|>` is skipped when the last assistant message has tool calls, empty content, and no later non-tool message).

This path is **not** the 2026-09-06 Jinja-400 (`part.get('type')` / `'str' object has no attribute 'get'`). That bug produced HTTP 400. Request2 here rendered and generated.

Falsifier: the **same** request2 payload with `temperature: 0` produced a following tool call. If the missing `<|turn>model>` suffix were sufficient to force EOS, temperature would not recover it.

### Not an OpenCode TUI freeze

`opencode.log` shows `exiting loop` after a completed stream. The model returned `stop` with nothing to execute.

### Not the earlier 404

Before the OpenCode model key was renamed, OpenCode sent `model: "gemma4"` and OVMS returned `Mediapipe graph definition with requested name is not found`. That is a separate client-id mismatch. The stall session used `gemma4-26-heretic` and got HTTP 200.

## Root causes (confirmed)

Two independent client/runtime couplings. Either is enough to make OpenCode stop; they stacked on this host.

### 1. Title agent contends on Profile E (`max_num_seqs: 1` + prefix cache)

OpenCode fires a title-generator request (`small=true`) against the **same** local model as the build agent.

Profile E is single-sequence with prefix caching. Title at 05:19:05 and main at 05:19:07 were both scheduled (`All requests: 2`). That is outside the E contract and pollutes the shared KV cache before request2.

### 2. Unspecified temperature → sampling EOS after the tool result

`BaseGenerationConfigBuilder` keeps the model temperature unless the request overrides it. Gemma 4 defaults sample. With no request seed, OVMS randomizes `rng_seed` per turn.

On `tool_choice=auto` after a tool result, that sampling often emits a handful of hidden/thinking tokens and EOS. OpenCode treats empty `stop` as “done”.

This matches the older Gemma4 finding in `docs/gemma4/ROOT-CAUSE-NOTES.md` (sampling variance at the action-selection boundary). It is not a new parser failure.

## Client mitigation (no OVMS restart)

Written to:

- `C:\Users\testc\.config\opencode\opencode.jsonc`
- `C:\Users\testc\.opencode\opencode.json`

Changes:

- `agent.title.disable: true`
- `small_model: opencode/ling-3.0-flash-fin-free` (title must not share the E GPU slot)
- `agent.build.temperature: 0`
- provider `extraBody`: `temperature: 0` and `chat_template_kwargs.enable_thinking: true`

Verification after that config (`opencode run --agent build -m ovms/gemma4-26-heretic`): `glob AGENTS.md` → `glob README.md` → 41-token text answer, not empty `stop`. No concurrent title request in the OVMS log.

OpenCode TUI must be restarted to pick this up.

## Still open (not required to explain this stall)

- Profile E `max_num_seqs: 1` remains hostile to any second local stream (compaction, title, parallel subagents).
- `auto` still has no triggered structured tags (`Gemma4GenerationConfigBuilder` clears `structured_output_config` on `auto`). That is a separate reliability issue.
- Session journals were not involved (`OVMS_SESSION_STORE_DIR` unset).
- Overlay generation-prompt after `tool_response` with thinking off is easy to misread as a bug; keep it documented as Google same-turn continuation, not as the cause of this OpenCode exit.
