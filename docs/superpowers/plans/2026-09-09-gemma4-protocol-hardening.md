# Gemma 4 Protocol Hardening Implementation Plan

> **Execution mode:** TDD-oriented hardening on `integration/gemma4-protocol-hardening-2026.5`. Do not replace the custom parser/generator stack. Do not call the work accepted until the Windows/OpenVINO machine campaign passes.

**Goal:** Align GEMMAMONSTER's Gemma4 generator with Google's canonical protocol while keeping a conservative recovery parser, strengthening regression coverage and observability without rewriting already-working components.

**Architecture:** `Gemma4GenerationConfigBuilder`, `Gemma4ReasoningParser`, and `Gemma4ToolParser` remain separate specialized components. `OutputParser` owns phase transitions. Generation is canonical; parsing is a tolerant superset. Hard required/named choices keep native Gemma4 structural tags and fail closed.

**Frozen external refs:** Google prompt-format page current on 2026-09-09; OVMS `a3a2abf287d5cb52f454bb1a1a55c0346cd44a35`; vLLM `e509d32b5a2f3d81dc949ff89f85c4c8f860ae29`; SGLang `ffe98a4279ba6e42d1f87dc4eeb6edb4887b9ea4`; llama.cpp `9cf3bf256b5a50a971a636c36dfe974387140687`; Transformers `5b7dcb0d36c242d8d85920a81c564ef3a86ca6dd`.

---

## Task 1: Freeze canonical-vs-recovery semantics in tests

**Files:**
- Modify: `src/test/llm/gemma4_fast/gemma4_reasoning_semantic_refit_test.cpp`

### Step 1.1 — Add canonical control case

Add a regression test proving the Google-documented sequence parses as:

```text
<|channel>thought\nNeed another tool<channel|><|tool_call>call:question{questions:[]}<tool_call|>
```

Expected:
- reasoning exactly `Need another tool`;
- exactly one `question` call;
- native argument normalization remains `{\"questions\":[]}`.

### Step 1.2 — Add exhaustive recovery boundary splits

For every byte split of `<|tool_call>` while `OutputParser` is in Gemma4 REASONING state:

1. feed `Need another tool` plus the prefix of the opener;
2. feed the remaining opener and the rest of the call;
3. drain parser phases;
4. assert the reasoning prefix is neither lost nor duplicated;
5. assert exactly one native tool call is recovered.

This is stronger than the existing single `<|tool_` split test and isolates the ownership boundary from general tool-body split coverage.

### Step 1.3 — Keep non-Gemma negative control

Existing `NonGemmaReasoningDoesNotTreatLiteralToolMarkerAsBoundary` remains mandatory. Recovery must stay opt-in via Gemma4 parsing config.

### Verification command on build machine

Run the dedicated Bazel target from `src/test/llm/gemma4_fast/BUILD` and record raw output. Do not infer PASS from compilation or source review.

---

## Task 2: Correct production semantics and add recovery trace

**Files:**
- Modify: `src/llm/io_processing/gemma4/gemma4_reasoning_parser.hpp`
- Modify: `src/llm/io_processing/output_parser.cpp`

### Step 2.1 — Correct misleading protocol comments

Replace statements equivalent to “Gemma4 permits direct thought -> tool” with:

- Google canonical output closes `<channel|>` before `<|tool_call>`;
- the direct tool opener is accepted only as a tolerant recovery boundary;
- vLLM/SGLang provide precedent for defensive tool-start interruption handling, but that is not the canonical serialization contract.

No state-machine behavior changes in this step.

### Step 2.2 — Emit explicit recovery trace

At the exact `REASONING -> TOOL_CALLS_PROCESSING_TOOL` recovery handoff, emit trace-level evidence containing:

- event name / unambiguous message (`Gemma4 recovery handoff`);
- preserved reasoning-prefix byte count;
- tool-start position.

Do not emit reasoning text itself in the new log message.

### Step 2.3 — Re-run Task 1 tests

Expected: canonical and recovery cases both pass; non-Gemma control unchanged.

---

## Task 3: Re-assert generator contract, change only if a test exposes a gap

**Files:**
- Review: `src/llm/io_processing/generation_config_builder.hpp`
- Review/Modify if needed: `src/test/llm/generation_config/gemma4_generation_contract_test.cpp`

Current audit says most required behavior is already implemented. Do not rewrite it for aesthetic consistency.

### Required assertions

1. `required` and named choices share hard-choice semantics.
2. named choice restricts available tags to the selected tool.
3. hard grammar allows direct tool or **canonical closed thought -> tool**.
4. hard grammar never uses an empty `ConstString` workaround.
5. hard constraint cannot be silently cleared after validation failure.
6. `auto` remains trigger-based and does not become `required`.
7. `parallel_tool_calls` controls repeatability.
8. `response_format` cannot silently replace active Gemma4 native tool constraints.

### Implementation rule

If these assertions already exist and source inspection matches them, record Task 3 as **no production delta required**. A no-op is preferable to manufacturing code churn.

---

## Task 4: Verify special-token and multi-turn ownership

**Files to inspect/test:**
- `src/llm/io_processing/output_parser.cpp`
- `src/llm/ovms_text_streamer.cpp`
- Gemma4 chat-template adapter/rendering tests under `src/test/llm/`

### Step 4.1 — Special token visibility

Prove that active Gemma4 reasoning/tool parser phases keep the control tokens needed for parsing even when ordinary content decoding would strip special tokens.

### Step 4.2 — Tool-result follow-up

Use Google's documented tool-call/tool-response sequence as a fixture. Verify:

- tool call is retained;
- tool response is placed in Gemma4's model/assistant turn representation;
- generation resumes at the correct model turn;
- reasoning required inside the same function-calling turn is not discarded prematurely.

### Step 4.3 — Completed-turn reasoning hygiene

Verify ordinary completed-turn raw reasoning is not blindly replayed into later standard turns.

Only patch chat-template handling if these tests expose an actual mismatch.

---

## Task 5: Machine acceptance campaign

**Target:** user's Windows/OpenVINO Gemma4 machine, using a build produced from the exact final branch SHA.

### Step 5.1 — Build

Record:

- source SHA;
- OpenVINO/OpenVINO GenAI versions;
- OVMS binary version;
- compiler/build command;
- build result.

### Step 5.2 — Fast parser/generator suites

Run and capture:

- Gemma4 fast parser contract target;
- Gemma4 reasoning semantic-refit target;
- Gemma4 generation contract target;
- parallel tool-call contract target;
- relevant chat-template tests.

### Step 5.3 — Live REST matrix

Exercise at minimum:

- `tool_choice=auto` with a tool call;
- `auto` with no tool call;
- `required`;
- named tool choice;
- wrong/unavailable named tool rejection;
- parallel tool calls;
- second-turn tool result;
- long CodeSleuth prompt;
- historical adversarial prompt.

Run two decoding profiles:

A. historical profile;
B. Google canonical `temperature=1.0`, `top_p=0.95`, `top_k=64`, fixed seed where supported.

### Step 5.4 — Evidence capture

For every live case capture:

- request body;
- **effective merged GenerationConfig**;
- parser trace around reasoning/tool transition;
- HTTP status;
- finish reason;
- completion token count;
- parsed tool name/arguments;
- raw response artifact.

### Step 5.5 — Acceptance decision

PASS only if:

- no expected tool call disappears into reasoning/content;
- no raw `<|tool_call>` body leaks as visible content;
- required/named never silently lose their constraint;
- parser tests and generator tests pass;
- no HTTP 5xx in the acceptance set;
- source SHA and evidence bundle are reproducible.

---

## Task 6: Final evidence commit and review

**Files:**
- Add machine acceptance report under `docs/superpowers/reports/`.
- Keep raw generated/runtime dumps outside Git unless they are compact, intentional evidence artifacts.

Before claiming completion:

1. re-resolve branch HEAD;
2. run verification commands fresh;
3. inspect Git diff against `ad19fc6d3934b5255be34059b07e52e0276e7168`;
4. request code review against the frozen design;
5. report exact green SHA and exact commands/results.

Do not merge this integration branch automatically.
