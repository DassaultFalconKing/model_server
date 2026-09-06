# Gemma4 Heretic Parser and Streaming Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make OVMS 2026.4 Gemma4 tool parsing resilient to realistic malformed/truncated outputs and streaming chunk boundaries, using the uncensored 26B derivative as an adversarial compatibility target without changing generation-tool enforcement.

**Architecture:** Keep the existing Gemma4 wire protocol and OpenAI response shape. Harden the parser at the model-output boundary: consume all immediately available state transitions, recover a usable in-flight call at generation end without inventing missing semantic data, and accept one documented Gemma4 terminator deviation. Keep Cursor's GenerationConfigBuilder work separate.

**Tech Stack:** C++17, OpenVINO GenAI, OVMS OutputParser, RapidJSON, GoogleTest, Windows OVMS 2026.4.

**Spec:** Existing Gemma4 parser contract plus observed robustness patterns from current vLLM, SGLang, and OVMS parser hardening PRs #4493/#4508/#4511.

## Global Constraints

- Base branch is `backport/gemma4-tool-parser-2026.4` at `6f5b48ece2078e32268b87402cc206e8b2772da8`.
- Do not modify GenerationConfigBuilder or Cursor's tool-guided-generation work.
- Preserve canonical Gemma4 syntax: `<|tool_call>call:name{...}<tool_call|>` with `<|\"|>` string delimiters.
- Never emit Gemma4 structural markers as OpenAI `content`.
- Recovery may close delimiters/braces at end-of-generation, but must not fabricate tool names, parameter names, or parameter values.
- Every production behavior change starts with a failing regression test.
- The heretic 26B lane is an adversarial acceptance lane; vanilla Gemma4 remains a short regression lane because tokenizer/template/stop behavior can differ.

---

### Task 1: Lock the known streaming failures with regression tests

**Files:**
- Create: `src/test/llm/output_parsers/gemma4_heretic_output_parser_test.cpp`

**Interfaces:**
- Consumes: `OutputParser::parseChunk`, `OutputParser::parse`, Gemma4 tokenizer fixture.
- Produces: regression coverage for complete-one-chunk calls, generation-end recovery, and alternate turn terminator behavior.

- [ ] **Step 1: Add a test where a complete tool call arrives in one streaming chunk**

Feed one complete `<|tool_call>...<tool_call|>` chunk followed by an empty `STOP` flush. Collect OpenAI deltas and require exactly one function name plus one complete JSON arguments object.

- [ ] **Step 2: Run the Gemma4 parser test target and verify RED**

Run:

```bash
bazel test //src:ovms_test --test_filter='Gemma4HereticOutputParserTest.*'
```

Expected: at least the single-chunk test fails because the current state machine advances only one parser state per `parseChunk()` invocation.

- [ ] **Step 3: Add end-of-generation truncated-call tests**

Cover an unterminated `<|\"|>` string and a complete bare value with a missing top-level `}`. Require recovery only for bytes already generated.

- [ ] **Step 4: Add a unary `<turn|>` terminator compatibility test**

Require `<|tool_call>call:name{...}<turn|>` to parse as a tool call. This is a known Gemma4 output variation handled by current vLLM.

- [ ] **Step 5: Commit RED tests**

```bash
git add src/test/llm/output_parsers/gemma4_heretic_output_parser_test.cpp
git commit -m "test: pin Gemma4 heretic streaming failures"
```

### Task 2: Consume available Gemma4 streaming state deterministically

**Files:**
- Modify: `src/llm/io_processing/gemma4/gemma4_tool_parser.cpp`
- Test: `src/test/llm/output_parsers/gemma4_heretic_output_parser_test.cpp`

**Interfaces:**
- Consumes: existing `State`, `parseNewContent()`, `streamingContent`, `streamingPosition`.
- Produces: one meaningful delta per call while advancing through non-emitting states until a delta can be emitted or no progress is possible.

- [ ] **Step 1: Change `parseChunk()` to loop through non-emitting state transitions**

The loop must stop immediately after emitting either the first tool-name delta or the arguments delta. It must also stop if neither state nor `streamingPosition` changes, preventing a spin loop.

- [ ] **Step 2: Fix the missing-end-tag branch in `parseInToolCallEndedState()`**

If neither another `call:` nor `<tool_call|>` is available, keep the parser waiting instead of doing arithmetic on `std::string::npos` and prematurely transitioning to `AfterToolCall`.

- [ ] **Step 3: Run the single-chunk regression test**

Expected: first backend chunk emits the name; the final empty flush emits arguments exactly once.

- [ ] **Step 4: Run all existing Gemma4 parser tests**

Expected: PASS with no duplicate arguments or content leakage.

- [ ] **Step 5: Commit**

```bash
git add src/llm/io_processing/gemma4/gemma4_tool_parser.cpp src/test/llm/output_parsers/gemma4_heretic_output_parser_test.cpp
git commit -m "fix: drain Gemma4 streaming parser states"
```

### Task 3: Recover usable truncated Gemma4 calls at generation end

**Files:**
- Modify: `src/llm/io_processing/gemma4/gemma4_tool_parser.hpp`
- Modify: `src/llm/io_processing/gemma4/gemma4_tool_parser.cpp`
- Test: `src/test/llm/output_parsers/gemma4_heretic_output_parser_test.cpp`

**Interfaces:**
- Produces: `bool finalizeToolCallOnGenerationEnd()` or equivalent private helper that only appends structural closure required to parse already-generated bytes.

- [ ] **Step 1: Verify the truncated-string and missing-brace tests fail**

- [ ] **Step 2: Implement minimal structural closure**

When generation ends in `ToolCallParameters` and a function name is already known: close an unmatched `<|\"|>` delimiter, append the missing top-level `}`, then reuse the normal parameter parser. Do not recover a call if no usable tool name was captured.

- [ ] **Step 3: Verify each recovery test passes independently**

- [ ] **Step 4: Run all Gemma4 parser tests**

- [ ] **Step 5: Commit**

```bash
git add src/llm/io_processing/gemma4/gemma4_tool_parser.hpp src/llm/io_processing/gemma4/gemma4_tool_parser.cpp src/test/llm/output_parsers/gemma4_heretic_output_parser_test.cpp
git commit -m "fix: recover truncated Gemma4 tool calls"
```

### Task 4: Accept the documented Gemma4 `<turn|>` terminator deviation

**Files:**
- Modify: `src/llm/io_processing/gemma4/gemma4_tool_parser.hpp`
- Modify: `src/llm/io_processing/gemma4/gemma4_tool_parser.cpp`
- Test: `src/test/llm/output_parsers/gemma4_heretic_output_parser_test.cpp`

**Interfaces:**
- Produces: alternate end-tag recognition for unary and streaming parsing without weakening tool-call start detection.

- [ ] **Step 1: Verify the `<turn|>` test is RED**

- [ ] **Step 2: Treat `<turn|>` as a valid tool-call terminator only after a valid Gemma4 tool call has started**

Do not globally reinterpret `<turn|>` as a tool call.

- [ ] **Step 3: Run focused and full Gemma4 parser tests**

- [ ] **Step 4: Commit**

```bash
git add src/llm/io_processing/gemma4/gemma4_tool_parser.hpp src/llm/io_processing/gemma4/gemma4_tool_parser.cpp src/test/llm/output_parsers/gemma4_heretic_output_parser_test.cpp
git commit -m "fix: tolerate Gemma4 turn terminator after tool call"
```

### Task 5: Add a local heretic 26B HTTP/SSE stress harness

**Files:**
- Create in deployment repo: `scripts/gemma4_toolcall_stress.py`
- Create in deployment repo: `docs/GEMMA4-TOOLCALL-HARDENING.md`

**Interfaces:**
- Consumes: OpenAI-compatible `/chat/completions`, configurable base URL/model, stream and non-stream modes.
- Produces: JSONL traces and aggregate pass rates for tool-call initiation, parser validity, duplicate deltas, marker leakage, and stream completion.

- [ ] **Step 1: Add repeated required/auto tool-call scenarios**

Include simple scalar args, strings containing commas/braces/HTML, nested arrays/objects, and tool results followed by a second turn.

- [ ] **Step 2: Preserve raw SSE frames before client normalization**

- [ ] **Step 3: Classify each run**

At minimum: `valid_tool_call`, `no_tool_call`, `malformed_args`, `marker_leak`, `duplicate_delta`, `stream_truncated`, `http_error`.

- [ ] **Step 4: Run on the local 26B heretic model on Arc 140V**

Acceptance target for `tool_choice=required` after Cursor's builder lands: 100% syntactically valid tool initiation in the fixed scenario set. Parser-only hardening is evaluated independently on outputs that contain a tool call.

- [ ] **Step 5: Run a short vanilla Gemma4 regression lane**

The vanilla lane confirms there is no tokenizer/template/stop regression; it is not replaced by the heretic result.

### Task 6: Verification and upstream-ready split

**Files:** none unless test/CI fixes are required.

- [ ] **Step 1: Run `Gemma4OutputParserTest.*` and `Gemma4HereticOutputParserTest.*`**
- [ ] **Step 2: Run formatter/style gates on touched C++ files**
- [ ] **Step 3: Review diff against base `6f5b48ece2078e32268b87402cc206e8b2772da8`**
- [ ] **Step 4: Keep generation-builder changes out of this branch**
- [ ] **Step 5: Prepare parser/streaming commits so they can be reviewed independently from upstream PR #4511**
