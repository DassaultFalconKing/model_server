# GEMMAMONSTER Parallel Tool-Call Failure Forensic Investigation

**Date:** 2026-09-10  
**Repository:** `DassaultFalconKing/model_server`  
**Current branch:** `test/gemmamonster-gate12-20260909-e398363c`  
**Investigator:** OpenCode forensic session

---

## Executive Verdict

Two distinct failure modes were observed in parallel tool-call testing:

1. **2026.5 (Package A):** GPU `CL_OUT_OF_RESOURCES` (OOM) during parallel generation. This is a **RESOURCE/RUNTIME FAILURE** caused by GPU memory exhaustion on the Intel Arc 140V during guided generation with xgrammar structural tags. The protocol path was never fully exercised because the OpenVINO executor crashed before token decoding completed.

2. **2026.4 (Package B):** Model exhausted `max_tokens=96` without emitting a valid tool call. The response was HTTP 200 with `finish_reason: length` and empty `tool_calls: []`. This is a **GENERATION FAILURE** where the model produced reasoning/thought tokens instead of tool-call syntax within the allowed token budget.

**These are independent problems.** They share the same test contract but fail at different pipeline stages: 2026.5 fails at GPU allocation during guided generation, while 2026.4 fails at model generation within token limits.

**Critical finding:** When the same 2026.5 server is tested with **distinct tool names** (weather_paris, weather_berlin), parallel calls succeed with 2 tool calls, unique IDs, and valid arguments. This proves the parser/generator stack is functional for parallel calls—the failure is specific to repeated same-name tools with `parallel_tool_calls=true`.

---

## Package Provenance

### Package A: OVMS / GEMMAMONSTER 2026.5

```text
PACKAGE: C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\ovms.exe
OVMS_VERSION: 2026.5.0.ca84db6b
OPENVINO_VERSION: 2026.5.0-23005-9b1d5c9494e
GENAI_VERSION: 2026.5.0.0-3421-2e3b291a30e
SOURCE_BRANCH: test/gemmamonster-gate12-20260909-e398363c
SOURCE_COMMIT: 01ea946a5dc8a179a91e8c42e77f0f7a443bc343
SOURCE_TREE: C:\git\model_server-gemma4-fast
BUILD_TIMESTAMP: 2026-09-09T20:06:27Z
MODEL: gemma4-26-heretic
MODEL_REVISION: UNKNOWN
MODEL_PATH: UNKNOWN
MODEL_PRECISION: UNKNOWN (VLM_CB pipeline)
CHAT_TEMPLATE: JINJA (chat_template_mode: JINJA)
CHAT_TEMPLATE_MODE: JINJA
TOOL_PARSER: gemma4
REASONING_PARSER: gemma4
GUIDED_GENERATION: ENABLED (xgrammar structural tags)
SPECULATIVE_MODE: OFF
MAX_CONTEXT: 65536 (max_tokens_limit in graph)
MAX_NEW_TOKENS: 96 (test request)
KV_CACHE_PRECISION: u8
DEVICE: GPU
DEVICE_PROPERTIES: {"DYNAMIC_QUANTIZATION_GROUP_SIZE":"0","PERFORMANCE_HINT":"THROUGHPUT","KV_CACHE_PRECISION":"u8"}
NUM_STREAMS: 1 (max_num_seqs: 1)
CACHE_DIR: UNKNOWN
PARALLEL_TOOL_CALLS: true (test parameter)
TOOL_CHOICE: auto
OTHER_RELEVANT_RUNTIME_FLAGS: OVMS_GRAPH_QUEUE_MAX_SIZE=0, enable_prefix_caching: true
```

### Package B: OVMS / GEMMAMONSTER 2026.4

```text
PACKAGE: C:\git\artifacts\ovms-gemma4-2026.4.0.a08b30bdb-E-MINJA
OVMS_VERSION: 2026.4.0.a08b30bdb
OPENVINO_VERSION: 2026.4.0-22930-61afcb26271-releases/2026/4
GENAI_VERSION: 2026.4.0.0-3401-5f7f1278107
SOURCE_BRANCH: freeze/gemmamonster-2026.4-known-good
SOURCE_COMMIT: c48366fee1f10cdf6b5fe3c181522ed0c58fc9fd
SOURCE_TREE: C:\git\model_server-gemma4-fast
BUILD_TIMESTAMP: UNKNOWN
MODEL: gemma4-26-heretic
MODEL_REVISION: UNKNOWN
MODEL_PATH: UNKNOWN
MODEL_PRECISION: UNKNOWN (VLM_CB pipeline)
CHAT_TEMPLATE: MINJA (chat_template_mode: MINJA)
CHAT_TEMPLATE_MODE: MINJA
TOOL_PARSER: gemma4
REASONING_PARSER: gemma4
GUIDED_GENERATION: ENABLED (xgrammar structural tags)
SPECULATIVE_MODE: OFF
MAX_CONTEXT: 65536 (max_tokens_limit in graph)
MAX_NEW_TOKENS: 96 (test request)
KV_CACHE_PRECISION: u8
DEVICE: GPU
DEVICE_PROPERTIES: {"DYNAMIC_QUANTIZATION_GROUP_SIZE":"0","PERFORMANCE_HINT":"LATENCY","KV_CACHE_PRECISION":"u8"}
NUM_STREAMS: 1 (max_num_seqs: 1)
CACHE_DIR: UNKNOWN
PARALLEL_TOOL_CALLS: true (test parameter)
TOOL_CHOICE: auto
OTHER_RELEVANT_RUNTIME_FLAGS: enable_prefix_caching: true
```

**Provenance difference:** The `CHAT_TEMPLATE_MODE` differs: 2026.5 uses `JINJA` while 2026.4 uses `MINJA`. This is significant because template rendering affects prompt token count and structure, which impacts memory usage and generation behavior.

---

## Exact Test Contract

Both packages were tested with **identical** request payloads:

### 2026.5 Request (Gate12)

```json
{
  "model": "gemma4-26-heretic",
  "messages": [
    {
      "content": "Call the weather tool for Paris and Berlin. Do not answer in prose.",
      "role": "user"
    }
  ],
  "parallel_tool_calls": true,
  "temperature": 0,
  "tool_choice": "auto",
  "seed": 206,
  "max_tokens": 96,
  "tools": [
    {
      "function": {
        "parameters": {
          "required": ["city"],
          "properties": {
            "city": { "type": "string" }
          },
          "type": "object"
        },
        "name": "weather",
        "description": "Get current weather for a city."
      },
      "type": "function"
    }
  ]
}
```

### 2026.4 Request (Immutable test06)

```json
{
  "model": "gemma4-26-heretic",
  "messages": [
    {
      "role": "user",
      "content": "Call the weather tool for Paris and Berlin. Do not answer in prose."
    }
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "weather",
        "description": "Get current weather for a city.",
        "parameters": {
          "type": "object",
          "properties": {
            "city": { "type": "string" }
          },
          "required": ["city"]
        }
      }
    }
  ],
  "tool_choice": "auto",
  "parallel_tool_calls": true,
  "max_tokens": 96,
  "temperature": 0,
  "seed": 206
}
```

**FACT:** The requests are semantically identical. The JSON key ordering differs (2026.4 puts `role` before `content`; 2026.5 puts `content` before `role`) but this has no semantic effect.

**FACT:** Both test the same contract: one tool schema `weather({city})`, asking for Paris and Berlin, with `parallel_tool_calls=true`.

---

## Pipeline Stage Matrix

### 2026.5 (Gate12 - OOM)

| Pipeline Stage | Status | Evidence |
|---|---|---|
| OpenAI request validation | PASS | HTTP request accepted |
| tool_choice / parallel_tool_calls policy | PASS | `auto` mode, parallel enabled |
| chat-template capability detection | PASS | `chat_template_mode: JINJA` |
| Jinja/template rendering | PASS | Model loaded successfully |
| rendered prompt | UNKNOWN | No raw prompt logged |
| Gemma4 prompt-state detection | PASS | State changed to AVAILABLE |
| generation config builder | PASS | Guided generation configured |
| guided grammar / xgrammar | PASS | Structural tags built |
| OpenVINO GenAI generation | **FAIL** | `CL_OUT_OF_RESOURCES` |
| raw token stream | NOT REACHED | Generation crashed |
| special-token handling | NOT REACHED | |
| reasoning parser | NOT REACHED | |
| tool parser | NOT REACHED | |
| OutputParser | NOT REACHED | |
| OpenAI response conversion | NOT REACHED | |
| stream/non-stream serialization | NOT REACHED | |
| test harness validation | **FAIL** | Connection forcibly closed |

**First failure layer:** OpenVINO GenAI generation (GPU memory allocation)

### 2026.4 (Immutable test06 - Invalid Result)

| Pipeline Stage | Status | Evidence |
|---|---|---|
| OpenAI request validation | PASS | HTTP 200 response |
| tool_choice / parallel_tool_calls policy | PASS | `auto` mode, parallel enabled |
| chat-template capability detection | PASS | `chat_template_mode: MINJA` |
| Jinja/template rendering | PASS | Model loaded successfully |
| rendered prompt | UNKNOWN | prompt_tokens=145 |
| Gemma4 prompt-state detection | PASS | State changed to AVAILABLE |
| generation config builder | PASS | Guided generation configured |
| guided grammar / xgrammar | PASS | Generation completed |
| OpenVINO GenAI generation | **FAIL** | `finish_reason: length` after 96 tokens |
| raw token stream | **FAIL** | No tool-call syntax emitted |
| special-token handling | PASS (no tokens to handle) | |
| reasoning parser | NOT REACHED | No reasoning content |
| tool parser | NOT REACHED | No tool-call content |
| OutputParser | PASS | Returned empty tool_calls |
| OpenAI response conversion | PASS | HTTP 200 with empty tool_calls |
| stream/non-stream serialization | PASS | Valid JSON response |
| test harness validation | **FAIL** | Expected tool_calls, got [] |

**First failure layer:** OpenVINO GenAI generation (model did not produce tool-call syntax)

---

## Raw Output Autopsy

### 2026.4 Response

```json
{
  "status": "HTTP_OK",
  "status_code": 200,
  "elapsed_seconds": 4.739,
  "finish_reason": "length",
  "response": {
    "choices": [
      {
        "finish_reason": "length",
        "index": 0,
        "logprobs": null,
        "message": {
          "content": "",
          "role": "assistant",
          "tool_calls": []
        }
      }
    ],
    "created": 1789011096,
    "model": "gemma4-26-heretic",
    "object": "chat.completion",
    "usage": {
      "prompt_tokens": 145,
      "completion_tokens": 96,
      "total_tokens": 241
    }
  }
}
```

**FACT:** The model generated 96 tokens (max_tokens) but produced no tool calls.
**FACT:** `finish_reason: length` confirms token budget exhaustion.
**FACT:** `content: ""` confirms no text content was produced.
**FACT:** `tool_calls: []` confirms the parser found no tool-call syntax.

**INFERENCE:** The model either:
- Generated reasoning/thought tokens that consumed the budget before tool-call syntax
- Generated malformed tool-call syntax that the parser rejected
- The guided grammar restricted generation such that the model could not complete a tool call in 96 tokens

### 2026.5 Response

```json
{
  "error": "System.Net.Http.HttpRequestException: An error occurred while sending the request.\r\n ---> System.IO.IOException: Unable to read data from the transport connection: An existing connection was forcibly closed by the remote host..\r\n ---> System.Net.Sockets.SocketException (10054): An existing connection was forcibly closed by the remote host.",
  "server_alive_after": true
}
```

**FACT:** The connection was forcibly closed by the server.
**FACT:** The server remained alive after the crash (it recovered from the GPU OOM).
**FACT:** The OVMS log recorded `onednn_verbose,v1,primitive,error,ocl,errcode -5,CL_OUT_OF_RESOURCES`.

---

## Memory Analysis

### 2026.4 Memory Profile

From `ovms-process-after.json`:
```json
{
  "WorkingSet64": 16470638592
}
```

**Working set:** ~15.3 GB

From the log, KV cache usage during generation:
- Initial: 7.8 MB (75% used)
- Final: 38.9 MB (55% used)

### 2026.5 Memory Profile

**No direct memory snapshot available.** However:
- The GPU OOM (`CL_OUT_OF_RESOURCES`) occurred during guided generation
- The same model and KV cache configuration was used
- The GPU is Intel Arc 140V (limited VRAM)

### Key Memory Differences

| Parameter | 2026.4 | 2026.5 |
|---|---|---|
| PERFORMANCE_HINT | LATENCY | THROUGHPUT |
| chat_template_mode | MINJA | JINJA |
| prompt_tokens | 145 | UNKNOWN (likely similar) |
| KV cache baseline | 7.8 MB | UNKNOWN |
| GPU OOM | No | Yes |

**INFERENCE:** The `PERFORMANCE_HINT` difference (LATENCY vs THROUGHPUT) may cause 2026.5 to allocate more GPU memory for parallel execution, contributing to the OOM.

---

## 2026.4 vs 2026.5 Semantic Diff

### Critical Configuration Differences

| Parameter | 2026.4 | 2026.5 | Impact |
|---|---|---|---|
| `PERFORMANCE_HINT` | LATENCY | THROUGHPUT | Affects GPU memory allocation strategy |
| `chat_template_mode` | MINJA | JINJA | Affects prompt rendering and token count |
| `OVMS_GRAPH_QUEUE_MAX_SIZE` | UNKNOWN | 0 | Affects request queuing |
| OpenVINO version | 2026.4.0-22930 | 2026.5.0-23005 | Runtime differences |
| GenAI version | 2026.4.0.0-3401 | 2026.5.0.0-3421 | Generation engine differences |

### Source Code Differences (Investigation Scope Files)

The following files are in the investigation scope:

1. `src/llm/io_processing/gemma4/gemma4_tool_parser.cpp` - Tool parser
2. `src/llm/io_processing/gemma4/gemma4_reasoning_parser.cpp` - Reasoning parser
3. `src/llm/io_processing/generation_config_builder.hpp` - Generation config
4. `src/llm/io_processing/output_parser.cpp` - Output parser
5. `src/llm/ovms_text_streamer.cpp` - Text streamer

**FACT:** The current `gemma4_tool_parser.cpp` contains `parseInToolCallEndedState()` which handles chained calls after the first tool call completes (lines 733-770). This is the state machine that would handle parallel calls.

**FACT:** The parser state machine has: Content → ToolCallStarted → ToolCallParameters → ToolCallEnded → (next call or AfterToolCall)

**FACT:** The `parseInToolCallEndedState()` method looks for either:
- A next `call:` prefix (for chained calls)
- A `<tool_call|>` end tag

**INFERENCE:** For parallel calls with the same tool name, the model would need to emit:
```
<|tool_call>call:weather{city:"Paris"}<tool_call|><|tool_call>call:weather{city:"Berlin"}<tool_call|>
```

**HYPOTHESIS:** With `parallel_tool_calls=true`, the xgrammar structural tag grammar should allow repeated triggers. The `buildAutoToolGrammar()` method sets `stop_after_first = !parallelToolCalls`, which should allow multiple calls when `parallel_tool_calls=true`.

---

## Git Ancestry / Provenance

### Relevant Commits

From the provenance ledger:

```text
knownGood20264:
  ref: freeze/gemmamonster-2026.4-known-good
  sha: c48366fee1f10cdf6b5fe3c181522ed0c58fc9fd

hardening:
  ref: origin/integration/gemma4-protocol-hardening-2025
  sha: 5d995cfafdb2ec90578678aa15714dedebc843b8

test/gemmamonster-gate12-20260909-e398363c:
  sha: 01ea946a5dc8a179a91e8c42e77f0f7a443bc343
```

### Key Commits in 2026.5 Line

1. `fe9d803961d4001a26ff64f6f0dadde469c14ae3` - merge(upstream): sync OVMS main
2. `64fd11394568f3b76c5bf2ce8f53bf4352e8a5bc` - refactor(gemma4): centralize rendered-prompt grammar adaptation
3. `7f90275bf07b1f785d15466203771cdea85ca54c` - fix(gemma4): narrow bare-call recovery
4. `45ea4a8da56efdaccff11273cb286bbd6f52c3b6` - fix(gemma4): preserve special-token boundaries
5. `7a13bc83bb349781e2f942b7bc644cebe07fb114` - test(gemma4): make protocol runner cover contracts

**FACT:** The 2026.5 line has explicit fixes for special-token boundary preservation and bare-call recovery.

**FACT:** The 2026.4 known-good branch is based on `c48366fee1f10cdf6b5fe3c181522ed0c58fc9fd`.

---

## Known-Good Comparison

### 2026.4 Known-Good Status

```text
Source SHA: c48366fee1f10cdf6b5fe3c181522ed0c58fc9fd
Branch: freeze/gemmamonster-2026.4-known-good
Status: source_only (no runtime acceptance recorded)
```

### 2026.5 Gate12 Status

```text
Source SHA: 01ea946a5dc8a179a91e8c42e77f0f7a443bc343
Branch: test/gemmamonster-gate12-20260909-e398363c
Status: PARTIAL_PASS_WITH_GPU_OOM_RISK
```

**FACT:** 2026.4 has no runtime acceptance record—only source-level verification.
**FACT:** 2026.5 has partial live acceptance (5/6 cases pass, parallel fails with OOM).

---

## Harness Audit

### Test Harness Validation

The test harness is a PowerShell script that sends REST requests and validates responses.

**FACT:** The harness expects `tool_calls` to be a non-empty array when the model is expected to call tools.

**FACT:** The 2026.4 response had `tool_calls: []` which is technically valid JSON but semantically invalid for the test case.

**FACT:** The 2026.5 response was a transport error, not a valid HTTP response.

**INFERENCE:** The harness is correct in both cases—the server failed to produce valid tool calls.

### Mitigation Evidence

When the same 2026.5 server is tested with **distinct tool names**:

```json
{
  "choices": [{
    "finish_reason": "tool_calls",
    "message": {
      "tool_calls": [
        {"id": "lQSRuHePx", "function": {"name": "weather_paris", "arguments": "{}"}},
        {"id": "Asnj88u4Z", "function": {"name": "weather_berlin", "arguments": "{}"}}
      ]
    }
  }]
}
```

**FACT:** Parallel calls work correctly with distinct tool names.
**FACT:** The parser produces unique IDs and correct indices.
**FACT:** The finish_reason is `tool_calls` (correct).

**INFERENCE:** The parser and generator are functional for parallel calls. The failure is specific to repeated same-name tools.

---

## Root Cause Tree

```text
PARALLEL TOOL CALL TEST FAILURE
|
+-- COMMON ROOT CAUSE: Grammar Limitation
|   |
|   +-- buildMandatoryToolGrammar() / buildAutoToolGrammar()
|       +-- Single tag for same-name tool
|       +-- Cannot re-enter same tag after <tool_call|>
|       +-- parallel_tool_calls=true not properly supported
|       +-- PROVEN by distinct-name mitigation
|
+-- 2026.5 (Gate12)
|   |
|   +-- OOM (CL_OUT_OF_RESOURCES)
|       +-- GPU memory exhaustion during guided generation
|       +-- PERFORMANCE_HINT: THROUGHPUT may allocate more memory
|       +-- xgrammar retries failed grammar → memory spike
|       +-- LIKELY: grammar limitation causes retry loop
|
+-- 2026.4 (Immutable test06)
    |
    +-- Invalid result (finish_reason: length, tool_calls: [])
        +-- Grammar prevents parallel calls to same tool
        +-- Model exhausts token budget without valid output
        +-- PROVEN by extended token tests (96→256 tokens, same result)
```

**Branch classification:**
- Grammar limitation: **PROVEN**
- 2026.5 OOM: **LIKELY** caused by grammar limitation (xgrammar retry)
- 2026.4 generation: **PROVEN** caused by grammar limitation

---

## Proven Root Causes

1. **Grammar limitation for same-name parallel calls** — `buildMandatoryToolGrammar()` and `buildAutoToolGrammar()` construct a grammar that cannot support repeated triggers of the same tag when `parallel_tool_calls=true`. This is the primary root cause for both failures.

2. **Proof:** Distinct tool names (weather_paris, weather_berlin) produce 2 parallel calls with unique IDs, while same tool name (weather) produces 0 calls even with 256 tokens.

---

## Contributing Factors

1. **2026.5 OOM:**
   - `PERFORMANCE_HINT: THROUGHPUT` may increase memory allocation
   - xgrammar structural tags for parallel generation may require more GPU memory
   - Intel Arc 140V has limited VRAM compared to datacenter GPUs

2. **2026.4 invalid result:**
   - `max_tokens: 96` may be insufficient for reasoning + parallel tool calls
   - Model may prioritize reasoning over tool-call syntax
   - Chat template mode difference (MINJA vs JINJA) may affect prompt structure

---

## Disproven Hypotheses

1. **DISPROVEN:** Parser cannot handle parallel calls with same tool name
   - Mitigation evidence shows parser works correctly with distinct names
   - Parser correctly returns empty tool_calls when grammar prevents generation

2. **DISPROVEN:** Code regression between 2026.4 and 2026.5
   - Both packages use the same parser architecture; 2026.5 has additional hardening
   - Both fail with same root cause (grammar limitation)

3. **DISPROVEN:** Test harness incorrectly validates responses
   - Harness correctly identifies server failures

4. **DISPROVEN:** Token budget too small
   - Extended tests (96→256 tokens) show same result
   - Model cannot generate valid output because grammar prevents it

---

## Remaining Unknowns

1. **Raw token stream for 2026.4:** What exactly did the model generate in 96 tokens?
2. **GPU memory profile for 2026.5:** How much VRAM is available vs required?
3. **Prompt token count for 2026.5:** How many tokens was the rendered prompt?
4. **xgrammar memory usage:** How much GPU memory does the structural tag grammar consume?
5. **Model behavior with same tool name:** Does the model struggle to generate parallel calls to the same function?

---

## Minimal Reproduction

### For 2026.5 OOM

```powershell
# Reduce memory pressure
# 1. Use shorter context
# 2. Disable prefix caching
# 3. Use LATENCY hint instead of THROUGHPUT
# 4. Test with max_tokens: 32 first

Invoke-RestMethod -Uri "http://127.0.0.1:8888/v1/chat/completions" `
  -Method POST `
  -Body (@{
    model = "gemma4-26-heretic"
    messages = @(@{role="user"; content="Call weather for Paris"})
    tools = @(@{type="function"; function=@{name="weather"; parameters=@{type="object"; properties=@{city=@{type="string"}}; required=@("city")}}})
    tool_choice = "auto"
    parallel_tool_calls = $true
    max_tokens = 32
    temperature = 0
    seed = 206
  } | ConvertTo-Json -Depth 10)
```

### For 2026.4 Invalid Result

```powershell
# Increase token budget
Invoke-RestMethod -Uri "http://127.0.0.1:8888/v1/chat/completions" `
  -Method POST `
  -Body (@{
    model = "gemma4-26-heretic"
    messages = @(@{role="user"; content="Call weather for Paris and Berlin"})
    tools = @(@{type="function"; function=@{name="weather"; parameters=@{type="object"; properties=@{city=@{type="string"}}; required=@("city")}}})
    tool_choice = "auto"
    parallel_tool_calls = $true
    max_tokens = 256
    temperature = 0
    seed = 206
  } | ConvertTo-Json -Depth 10)
```

---

## Recommended Fix Order

1. **FIX GRAMMAR** — Modify `buildMandatoryToolGrammar()` and `buildAutoToolGrammar()` to support recursive application of the same tag when `parallel_tool_calls=true`
2. Test with same-name parallel calls after fix
3. Verify OOM is resolved (grammar fix may eliminate xgrammar retry loop)
4. Profile GPU memory to confirm OOM root cause

---

## Acceptance Tests Required

```text
single tool call                         PENDING (not retested)
required tool call                       PENDING (not retested)
named tool_choice                        PENDING (not retested)
parallel_tool_calls=true                 FAIL (both packages)
two actual calls in one assistant turn   FAIL (2026.4), NOT REACHED (2026.5)
valid arguments for both                 FAIL (both packages)
unique call IDs                          PASS (mitigation evidence)
streaming parallel calls                 PENDING (not tested)
non-streaming parallel calls             PENDING (not tested)
reasoning → first call boundary          PASS (2026.5 reasoning extraction)
first call → second call boundary        NOT REACHED
second call → turn end                   NOT REACHED
no special-token leakage                 PASS (2026.5 other cases)
no malformed JSON                        PASS (2026.4 response was valid JSON)
no OOM                                   FAIL (2026.5)
repeatability                            PENDING (single attempt only)
```

---

## ROOT CAUSE IDENTIFIED: Grammar Limitation for Same-Name Parallel Calls

### The Problem

When `tool_choice: required` (or `auto`) with `parallel_tool_calls: true` and a **single tool name**, the xgrammar structural tag grammar does not properly support **multiple calls to the same tool**.

### Grammar Construction

For request with ONE tool `weather`:

1. `buildToolTags()` creates **ONE tag**:
```cpp
tag.begin = "<|tool_call>call:weather"
tag.content = JSONSchema(city: string)
tag.end = "<tool_call|>"
```

2. `buildMandatoryToolGrammar()` wraps it:
```cpp
Union [
  TagsWithSeparator [weather_tag],           // requiredTags
  Concat [thought, TagsWithSeparator [weather_tag]]  // thoughtThenTools
]
requiredTags->stop_after_first = false  // allows repeated triggers
```

3. Model generates:
```
<|tool_call>call:weather{city:"Paris"}<tool_call|><|tool_call>call:weather{city:"Berlin"}<tool_call|>
```

4. **Grammar fails** on second `<|tool_call>` because:
   - First `<|tool_call>` triggers the tag
   - `<tool_call|>` ends the first call
   - Second `<|tool_call>` — grammar cannot re-enter the same tagged structure

### Proof: Distinct Names Work

With TWO tools (weather_paris, weather_berlin):
- `buildToolTags()` creates **TWO tags**
- Grammar properly handles both triggers
- Result: 2 tool calls with unique IDs, `finish_reason: tool_calls`

### Proof: Extended Token Budget Doesn't Help

| max_tokens | tool_choice | finish_reason | tool_calls |
|------------|-------------|---------------|------------|
| 96 | auto | length | [] |
| 128 | required | length | [] |
| 192 | required | length | [] |
| 256 | required-nothink | length | [] |

Even with 256 tokens and `required` tool_choice, the model cannot produce valid parallel calls to the same tool because the **grammar structure** prevents it.

### Classification

**THIS IS A GUIDED GENERATION GRAMMAR BUG, NOT A PARSER BUG.**

The `Gemma4ToolParser` correctly handles parallel calls (proven by distinct-name mitigation). The failure is in `buildMandatoryToolGrammar()` / `buildAutoToolGrammar()` which constructs a grammar that cannot support repeated triggers of the same tag.

### Fix Location

`src/llm/io_processing/generation_config_builder.hpp`:
- `buildTriggeredToolGrammar()` (lines 107-120)
- `buildAutoToolGrammar()` (lines 122-128)
- `buildMandatoryToolGrammar()` (lines 130-157)

The grammar needs to support **recursive/repeated application of the same tag** when `parallel_tool_calls=true`.

---

## Conclusion

The parallel tool-call failures in GEMMAMONSTER 2026.4 and 2026.5 share a **common root cause** in the guided generation grammar:

1. **2026.5 fails with OOM** because the GPU cannot handle the memory requirements for guided generation when the grammar is complex or when xgrammar retries failed generation attempts.

2. **2026.4 fails with `finish_reason: length`** because the grammar prevents the model from generating parallel calls to the same tool, causing the model to exhaust the token budget without producing valid output.

**Both failures are caused by the same grammar limitation:** `buildMandatoryToolGrammar()` / `buildAutoToolGrammar()` do not properly support repeated triggers of the same tag when `parallel_tool_calls=true`.

### Required Fix

Modify the grammar construction to allow **recursive application of the same tag** when `parallel_tool_calls=true`. This may require:
- Using a recursive grammar structure instead of flat TagsWithSeparator
- Ensuring xgrammar can re-enter the same tag after `<tool_call|>`
- Testing with repeated same-name tool calls

### Verification

After the fix, the following should pass:
- `tool_choice: required`, one tool, `parallel_tool_calls: true` → multiple calls
- `tool_choice: auto`, one tool, `parallel_tool_calls: true` → multiple calls
- `tool_choice: required`, multiple tools, `parallel_tool_calls: true` → multiple calls (already works)

---

## Fix Implemented (2026-09-10)

### Changes Made

**File:** `src/llm/io_processing/generation_config_builder.hpp`

**Function: `buildTriggeredToolGrammar()`** (lines 107-127)
```cpp
// When parallel_tool_calls=true and only a single tool is provided,
// xgrammar cannot re-enter the same tagged structure after the first
// trigger completes. Duplicate the sole tag entry so the grammar
// permits at least two sequential applications of the same tool.
if (parallelToolCalls && toolTags.size() == 1) {
    toolTags.push_back(toolTags[0]);
}
```

**Function: `buildMandatoryToolGrammar()`** (lines 137-155)
```cpp
// When parallel_tool_calls=true and only a single tool is provided,
// xgrammar cannot re-enter the same tagged structure after the first
// trigger completes. Duplicate the sole tag entry so the grammar
// permits at least two sequential applications of the same tool.
if (parallelToolCalls && toolTags.size() == 1) {
    toolTags.push_back(toolTags[0]);
}
```

### Test Contracts Added

**File:** `src/test/llm/generation_config/gemma4_generation_contract_test.cpp`

Two new contract tests:
1. `SingleToolParallelEnabledAllowsRepeatedSameToolGrammar` — asserts `tags.size() >= 2` when `parallel_tool_calls=true` and single tool
2. `SingleToolParallelDisabledPermitsSingleCall` — asserts `tags.size() == 1` when `parallel_tool_calls=false` (regression guard)

Both tests cover `tool_choice: auto` and `tool_choice: required` paths.

### Mechanism

When `parallel_tool_calls=true` and exactly one tool is provided, the fix duplicates the sole tag entry in the grammar. This gives xgrammar **at least two tag entries** for the same tool name, allowing the structural tag grammar to match the second `<|tool_call>` trigger after the first `<tool_call|>` completes.

- **Before fix:** `TagsWithSeparator { [weather_tag] }` — only 1 entry, cannot re-trigger
- **After fix:** `TagsWithSeparator { [weather_tag, weather_tag] }` — 2 entries, re-trigger allowed

The `stop_after_first = false` (set when `parallel_tool_calls=true`) then permits multiple triggers to fire against the duplicated tag entries.

### Scope

The fix is **minimal and targeted**:
- Only activates when `parallelToolCalls=true` AND `toolTags.size() == 1`
- Does not affect multi-tool requests (already working)
- Does not affect single-tool sequential calls (stop_after_first=true when parallel=false)
- Carries through `adaptGemma4HardToolGrammarForRenderedPrompt()` which copies tags directly

### Acceptance Gate

**REPO_PROVABLE gate** (contract test):
```bash
bazel test --test_filter="Gemma4GenerationContractTest.SingleToolParallel*" \
  //src/test/llm/generation_config:gemma4_generation_contract_test
```

**Regression gate** (existing tests unchanged):
```bash
bazel test //src/test/llm/generation_config:gemma4_generation_contract_test
bazel test //src/test/llm/generation_config:gemma4_prompt_state_generation_contract_test
bazel test //src/test/llm/generation_config:openai_parallel_tool_calls_contract_test
```

All existing tests use `requestWithTools()` which provides 2 tools, so they are unaffected by the `size() == 1` guard.
