# Handoff: Gemma4 Google-template session-state staging

**To:** the programmer staging this branch  
**From:** agent session on `fix/gemma4-google-template-session-state`  
**Date:** 2026-09-06  
**Ask:** review the uncommitted code below, then make the remaining issues disappear. Do not merge until live `required` and restart-resume are PASS and debug probes are gone.

This worktree is **not** the 316-trial reliability campaign (`908bc8b7` / Wondernutts). Do not mix those identities.

---

## Purpose of the job

Ship OVMS at `8f84ec0a` against the **canonical Google Gemma 4 chat template** (not Wondernutts jinja), with:

1. JINJA chat-template path on Windows + newest OpenVINO/GenAI.
2. Multi-turn tool calling that survives request2 (assistant tool_call → tool result → `publish_review_evidence`).
3. Session persistence (`X-OVMS-Session-ID`, seed omit vs explicit, restart-proof resume).
4. Live acceptance: `named` / `required` / `auto` via `ab-evidence/live_chain_harness.py`.

The product under test is this worktree’s `ovms.exe`, overlay  
`C:\llm\models\runtime\gemma4-26-heretic-google-current`, REST **18000**, profile `vlm-stable`, `ChatTemplateMode JINJA`.

---

## Identity (do not drift)

| Item | Value |
|---|---|
| Repo | `C:\git\model_server-gemma4-google-template-session-state` |
| Branch | `fix/gemma4-google-template-session-state` |
| HEAD (committed) | `8f84ec0aca067f6b06a6eaf33db799037130c57f` |
| BASE | `7300995129f5686fe7ec6999905031399698745e` |
| Overlay | `C:\llm\models\runtime\gemma4-26-heretic-google-current` |
| Google model | `google/gemma-4-26B-A4B-it` rev `4d7ae4984b7db7de8f8457170b3f1a419ee76d52` |
| Template SHA256 | `ae53464bf3be25802b3a5b37def7fd89667067d7577049b3b2d74c4d8de4c6d4` |
| OpenVINO | `2026.4.0-22930-61afcb26271-releases/2026/4` — always pass `-OpenVinoDir C:/opt/openvino/runtime/cmake` |
| GenAI | `2026.4.0.0-3401-5f7f1278107` |
| Launch | `C:\git\gemmamonster-acceptance\ovms\gemma4-diagnostic-pack\launch.ps1` |
| Session store env | `OVMS_SESSION_STORE_DIR=C:\llm\ovms-session-store-8f84ec0a` (dir stayed **empty**) |
| Binary after Jinja fix | SHA256 `71d2b983565c24aeacb80726ab92ef81f78296a8df628a74aa20a2b818394e96` (Dev rebuild; log stamp `REPLACE_PROJECT_VERSION`) |

Do **not** source `C:\llm\ovms\setupvars.ps1` (broken `PYTHONHOME`). Use `PYTHONHOME=C:\opt\Python312`.

---

## What this session did

### 1. Isolated and built `8f84ec0a`

- Fast contracts on clean SHA: `gemma4_generation_contract_test`, `gemma4_parser_contract_test` — PASS.
- `windows_build_fast -Mode Verify -WithPython $true -OpenVinoDir C:/opt/openvino/runtime/cmake` — **build** PASS (ovms_test was linked, **not executed**).
- Two MSVC workarounds required to compile (still dirty, not the Jinja bug):
  - `src/llm/servable.cpp` — C4239: named `rapidjson::Value seedName` before `AddMember`.
  - `src/test/llm/output_parsers/gemma4_v2_contract_test.cpp` — `EXPECT_THAT`/`HasSubstr` → `string::find` (`gmock` target missing).

### 2. Live named request2 was HTTP 400

```
Calculator::Process() for node "LLMExecutor" failed:
'str object' has no attribute 'get'
```

Google `chat_template.jinja` line 300: `part.get('type')`. Jinja2 treats a **dict as a sequence**, so converting role=`tool` JSON `content` to an object made the OpenAI forward-scan iterate **dict keys** (strings).

Reproducer (no GPU):  
`C:\opt\Python312\python.exe ab-evidence\debug_jinja_str_get.py`  
(`PYTHONHOME=C:\opt\Python312`, do not prefix with `py`).

| Render | Result |
|---|---|
| Raw HTTP (arguments string) | Custom mapping error at line 258, **not** `.get` |
| Arguments object + content object | **exact** `'str object' has no attribute 'get'` @ line 300 |
| Arguments object + content **string** | OK |

### 3. Production fix (keep this; strip the logs)

`src/llm/io_processing/chat_template/analyzer.cpp` — Gemma4 caps:

```cpp
parseToolResponseJsonContent = mapsResponse && !iteratesPartsWithGet;
```

where `iteratesPartsWithGet` is `part.get('type')`. Google overlay then keeps tool content as a JSON **string**; object `arguments` still come from the dry-run probe (`requiresObjectArguments=true`).

Tests added in `src/test/llm/chat_template_analyzer_test.cpp` (not executed in `ovms_test` this session).

Live proof after rebuild+restart: named seed=42 request2 HTTP 200, exact SHA, 220 completion tokens.

### 4. Live scoreboard after the Jinja fix

Full table: `ab-evidence/newest-runtime/status.json`.

| Chain | Verdict | Notes |
|---|---|---|
| named seed=42 | **PASS** | request2 HTTP 200, exact SHA |
| named omit-seed | **PASS** | needed `--max-tokens 4096`; 1024 → `finish_reason=length`, empty `tool_calls` |
| auto seed=42 | **PASS** | |
| required seed=42 | **FAIL** | HTTP 200, `finish_reason=length`, `tool_calls=[]`, burned 4096 tokens, empty content |
| named resume after OVMS kill | **FAIL** | store empty; request2 same length/empty-calls at 1024 and 4096 |

Jinja-400 is gone. Remaining failures are **tool_choice=required**, **session journal persistence**, and **restart resume**.

---

## Uncommitted files to review (this repo)

Keep / land:

| Path | Why |
|---|---|
| `src/llm/io_processing/chat_template/analyzer.cpp` | Real fix. **Delete** the `debug-afec93.log` probe (`#region agent log`). |
| `src/test/llm/chat_template_analyzer_test.cpp` | Contracts for the new heuristic. Run `ChatTemplateAnalyzerTest.*` in `ovms_test`. |
| `src/llm/servable.cpp` | MSVC C4239 workaround — review if there is a cleaner AddMember form. |
| `src/test/llm/output_parsers/gemma4_v2_contract_test.cpp` | MSVC/gmock workaround — review; prefer real gmock if the target exists. |

Remove before merge (session debug probes, hardcoded `C:\git\model_server-gemma4-clean\debug-afec93.log`):

| Path | Why |
|---|---|
| `src/llm/io_processing/input_processors/chat_template_adapter.cpp` | Debug NDJSON only |
| `src/llm/py_jinja_template_processor.cpp` | Debug `_agent_log` in embedded Python |
| `ab-evidence/debug_jinja_str_get.py` | Local Jinja reproducer; keep only if you want it as a test fixture |

Harness tweak (optional, evidence-only):

| Path | Why |
|---|---|
| `ab-evidence/live_chain_harness.py` | `--max-tokens` for request2 (default still 1024) |

Evidence (do not treat as source of truth for merge): `ab-evidence/newest-runtime/`.

---

## Issues that must disappear

Please review the analyzer heuristic and the dirty tree, then fix these so staging can close:

1. **Strip debug instrumentation** from `analyzer.cpp`, `chat_template_adapter.cpp`, `py_jinja_template_processor.cpp`. Rebuild. Confirm no writes to `debug-afec93.log`.

2. **`tool_choice=required` on request2**  
   Evidence: `ab-evidence/newest-runtime/live-required-seed42/request2-response.json`  
   HTTP 200, `finish_reason=length`, `tool_calls=[]`, 4096 completion tokens, empty `content`.  
   Named/auto on the same model emit `publish_review_evidence`. Gemma4 `Gemma4GenerationConfigBuilder` treats `required` as hard structured output (`generation_config_builder.hpp`). Find why guided generation + thinking produces no parsed tool call.

3. **Session store never writes**  
   `OVMS_SESSION_STORE_DIR=C:\llm\ovms-session-store-8f84ec0a` was set at launch; directory stayed empty. Restart-proof resume cannot work without journals. Trace `SessionStateStore` / `X-OVMS-Session-ID` on this binary.

4. **Restart resume**  
   `ab-evidence/newest-runtime/live-named-resume/` — checkpoint request1 PASS; after OVMS restart, request2 length-outs even at 4096. May be (3) plus the same thinking-budget issue as omit-seed@1024.

5. **MSVC compile on clean `8f84ec0a`**  
   Verify/Package must build without ad-hoc workarounds, or land those two patches properly (servable AddMember, gmock vs `string::find`).

6. **Run the analyzer tests** that were added but never executed (`//src:ovms_test` `--gtest_filter=ChatTemplateAnalyzerTest.*`).

Do not “fix” Google `chat_template.jinja` in the overlay unless review proves the OVMS adapter/analyzer is wrong. Live named/auto already pass with content left as a string.

---

## How to reproduce live

```powershell
# env: PYTHONHOME=C:\opt\Python312; do not source C:\llm\ovms\setupvars.ps1
# OpenVinoDir must be explicit
Set-Location C:\git\model_server-gemma4-google-template-session-state
.\windows_build_fast.ps1 -Mode Dev -WithPython $true -SkipFastTests -OpenVinoDir "C:/opt/openvino/runtime/cmake"

# launch
# OVMS_SESSION_STORE_DIR=C:\llm\ovms-session-store-8f84ec0a
# launch.ps1 -OvmsExe bazel-bin\src\ovms.exe
#   -ModelPath C:\llm\models\runtime\gemma4-26-heretic-google-current
#   -ModelName gemma4-26-heretic -Profile vlm-stable -RestPort 18000 -ChatTemplateMode JINJA

C:\opt\Python312\python.exe ab-evidence\live_chain_harness.py `
  --base-url http://127.0.0.1:18000 --model gemma4-26-heretic `
  --repo-root C:\git\model_server-gemma4-google-template-session-state `
  --commit-sha 8f84ec0aca067f6b06a6eaf33db799037130c57f `
  --catalog ab-evidence\complex-tool-catalog.json `
  --out-dir ab-evidence\newest-runtime\<run-id> `
  --second-tool-choice named --seed 42 --temperature 0.0
```

`required` / `--omit-seed` / `--stop-after-tool-result` + `--resume` as in `ab-evidence/live_chain_harness.py`.

---

## Review request

Please review this dirty tree as if it were a PR against `8f84ec0a`:

- Is `mapsResponse && !iteratesPartsWithGet` the right capability, or should the adapter/template path check `tool_body is mapping` before `is sequence`?
- Are the two MSVC workarounds acceptable on `main`?
- Why does `required` generate 4096 tokens of unparsed thinking?
- Why does the session store stay empty when the env var is set?

Then make issues 1–6 disappear: clean probes, green `required`, journals on disk, PASS resume, Verify without local hacks, analyzer tests actually run.

Evidence index: `ab-evidence/newest-runtime/status.json`.
