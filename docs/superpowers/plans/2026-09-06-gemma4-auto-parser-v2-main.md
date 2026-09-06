# Gemma4 Auto Tool-Calling V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land a production-ready Gemma4 auto tool-calling path on `main` with native auto generation, canonical Google template compatibility, a recursive bounded parser, explicit repository wiring, and acceptance tooling for real OpenCode workloads.

**Architecture:** Keep the five vectors separate: Generator, Parser, Template, repository wiring, and official-doc conformance. `tool_choice=auto` must use native Gemma4 generation and post-generation parsing. `required` and named tool choices remain fail-closed constrained generation. Parser v2 uses recursive native-value parsing, tokenizer-resolved structural markers, bounded recovery, and tool-registry awareness while preserving atomic complete-call emission.

**Tech Stack:** C++17, OpenVINO GenAI StructuredOutputConfig, RapidJSON, OVMS OutputParser/GenerationConfigBuilder, Jinja chat templates, Bazel/gtest, PowerShell/Python acceptance harnesses.

**Spec:** `docs/superpowers/plans/2026-09-06-gemma4-auto-parser-v2-main.md`

## Global Constraints

- Target branch is `main`; user explicitly authorized direct main integration.
- Preserve current upstream-derived `main` behavior outside Gemma4.
- `auto` must not install Gemma4 structured-output constraints.
- `required` and named choices must remain fail-closed.
- Do not silently execute malformed or unknown tool syntax.
- Parser output remains atomic at complete-call boundaries.
- Google Gemma4 tool-calling/template semantics are protocol authority; vLLM/SGLang/Dynamo are peer references, not the spec.
- Do not claim test PASS without observed test/CI evidence.

---

### Task 1: Generator Contract

**Files:**
- Create: `src/llm/io_processing/gemma4/generation_config_builder.hpp`
- Create: `src/llm/io_processing/gemma4/generation_config_builder.cpp`
- Modify: `src/llm/io_processing/generation_config_builder.hpp`
- Test/Create: `src/test/llm/generation_config/gemma4_generation_contract_test.cpp`
- Test/Create: `src/test/llm/generation_config/BUILD`

**Interfaces:**
- Consumes: `OpenAIRequest::{toolChoice,toolNameSchemaMap,responseFormat}`
- Produces: `Gemma4GenerationConfigBuilder::parseConfigFromRequest(const OpenAIRequest&)`

- [ ] Write tests proving `auto` leaves `structural_tags_config` unset for an OpenCode-like `question` schema.
- [ ] Write tests proving `required` and named choices install immediate `TagsWithSeparator` constraints and reject missing schemas.
- [ ] Write tests proving response-format/tool-constraint collision fails closed.
- [ ] Add `Gemma4GenerationConfigBuilder` and wire it through `GenerationConfigBuilder`.
- [ ] Verify target tests in CI/local runner.

### Task 2: Parser V2 Contract

**Files:**
- Modify: `src/llm/io_processing/gemma4/gemma4_tool_parser.hpp`
- Modify: `src/llm/io_processing/gemma4/gemma4_tool_parser.cpp`
- Modify: `src/llm/io_processing/output_parser.cpp`
- Test: `src/test/llm/output_parsers/gemma4_output_parser_test.cpp`
- Test/Create: `src/test/llm/output_parsers/gemma4_reviewed_contract_test.cpp`

**Interfaces:**
- Consumes: decoded Gemma4 native syntax and request tool registry.
- Produces: `ToolCall` with valid JSON arguments only after a complete bounded call.

- [ ] Add failing tests for recursive `array<object>`, nested arrays/objects, booleans, integers, floats and null.
- [ ] Add failing tests for `call:name(...)`, `<|tool_call>:name{...}`, and reasoning-end→`call:name{...}` variants.
- [ ] Add failing tests proving `<tool_call|>` bounds malformed calls and a later valid call survives.
- [ ] Replace ad-hoc object/array conversion with a recursive native-value parser that preserves RapidJSON scalar typing.
- [ ] Normalize only structurally anchored call-header variants; no global fuzzy matching.
- [ ] Pass the actual tool registry into `Gemma4ToolParser` and reject/classify unknown executable calls safely.
- [ ] Preserve atomic complete-call emission and existing upstream special-token/remainder behavior.

### Task 3: Template Contract and Diff Review

**Files:**
- Create: `docs/gemma4/google-template-contract.md`
- Create: `tests/functional/llm/gemma4_template_contract.py` or nearest existing functional-test location.
- Deployment helper repository: update the existing Gemma4 launch/helper script that injects `chat_template.jinja` into the model directory.

**Interfaces:**
- Consumes: pinned Google Gemma4 canonical `chat_template.jinja` revision.
- Produces: model-directory `chat_template.jinja` used by both OVMS JINJA and tokenizer/minja paths.

- [ ] Record pinned upstream source/revision and semantic diff expectations.
- [ ] Test tool declaration serialization, assistant tool calls, role=tool responses, reasoning preservation on tool turns, turn closure, arrays/objects/null/bools.
- [ ] Update deployment helper to fetch/copy the pinned template idempotently with backup and SHA verification.
- [ ] Verify OVMS template analyzer/probe recognizes the resulting template as Gemma4 tool-capable.

### Task 4: Repository Wiring Audit

**Files:**
- Create: `docs/gemma4/tool-calling-callgraph.md`
- Modify where required: `src/llm/apis/openai_api_handler.cpp`, `src/llm/io_processing/output_parser.cpp`, `src/llm/io_processing/generation_config_builder.hpp`

**Interfaces:**
- Trace: HTTP request → `parseTools()` → `OpenAIRequest` → `GenerationConfigBuilder` → template/input request → GenAI → `OutputParser` → Gemma4 reasoning/tool parser → OpenAI response.

- [ ] Document the exact call graph and data ownership for `toolChoice`, tool schemas, template kwargs and parser selection.
- [ ] Assert the same tool registry reaches generation and parser layers.
- [ ] Add trace diagnostics at generator/parser/template boundaries sufficient to classify failures as G/T/M/P/W.

### Task 5: Acceptance Harness

**Files:**
- Create: `scripts/gemma4-toolcall-acceptance.ps1`
- Create: `scripts/gemma4-toolcall-matrix.py`
- Create: `docs/gemma4/acceptance-runbook.md`

**Interfaces:**
- Consumes: running OVMS URL/model name.
- Produces: exact request/response/SSE evidence and a concise PASS/FAIL matrix.

- [ ] Cover none, auto optional, auto expected, required, named, nested objects, arrays, OpenCode `question`, parallel calls, streaming, roundtrip, post-tool recovery and reserved-token detection.
- [ ] Ensure CLI flags cannot accidentally reinterpret `--mode all` as the model name.
- [ ] Save raw request, raw response, SSE, `/v1/models`, and concise summary per case.
- [ ] Add a tokenizer-marker diagnostic for `<|tool_call>`, `<tool_call|>`, `<|channel>`, `<channel|>`, `<|turn>`, `<|\"|>`, `<unused27>`, `<unused45>`.

### Task 6: Verification and Main Handoff

- [ ] Re-resolve `main` before each write batch to avoid overwriting concurrent upstream work.
- [ ] Run available CI/status checks and inspect logs for the exact final SHA.
- [ ] Do not label runtime accepted until the Arc 140V / Wondernuttz model matrix passes.
- [ ] Produce a Luna Reserve deployment prompt pinned to the exact final main SHA, with build, launch, template injection and acceptance commands.
