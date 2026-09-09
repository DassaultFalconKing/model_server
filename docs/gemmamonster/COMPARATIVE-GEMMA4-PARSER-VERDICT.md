# Comparative Gemma 4 Parser Verdict

**Status:** integration verdict  
**Date:** 2026-09-09  
**Target:** `integration/gemma4-protocol-hardening-2026.5`  
**Baseline before this document:** `52c6b534dab9cb2cb413eb175541870785cdd2c3`  
**OVMS 2026.4 known-good reference:** `freeze/gemmamonster-2026.4-known-good` @ `c48366fee1f10cdf6b5fe3c181522ed0c58fc9fd`

This document is an implementation verdict, not a greenfield design. It compares the current Gemmamonster implementation with Google Gemma 4 protocol material and the independent serving implementations in vLLM, SGLang and llama.cpp. Transformers is used as a protocol/parser reference where it is part of those stacks.

Evidence labels used below:

- **VERIFIED**: directly supported by source, commit, issue, test, or canonical template inspected for this verdict.
- **INFERENCE**: architectural conclusion from multiple verified sources.
- **UNKNOWN**: not established strongly enough to use as an implementation premise.

## 1. Executive verdict

Gemmamonster is **not missing a Gemma 4 parser stack**. On the 2026.5 integration line it already contains a native OVMS Gemma 4 tool parser, a model-native reasoning parser, guided tool generation, OpenAI request-policy handling, rendered-prompt/template adaptation, persistent tool-loop/session continuity, special-token streaming handoff, and an explicit protocol-hardening acceptance runner.

The project history supports the intended provenance model: tool-generation ideas were taken from llama.cpp's specialized Gemma 4 handling, while tool/reasoning parsing behavior was refitted from the vLLM lineage into OVMS abstractions. The resulting code is not a mechanical transplant. The clearest proof is the reasoning parser refactor from `Qwen3ReasoningParser` inheritance to OVMS `BaseOutputParser`, plus later fixes that model Gemma-specific phase transitions and streamer behavior directly.

The remaining work is therefore **conformance hardening and drift control**, not another parser rewrite.

The canonical protocol authority must remain Google's current Gemma 4 prompt format and canonical chat template. Peer runners are evidence about robust parsing behavior and failure modes, not authorities that may redefine Google's wire format. In particular, the current integration branch correctly documents canonical `thought -> <channel|> -> <|tool_call>` ordering and treats missing-close / bare-call recovery as tolerance only.

**Promotion verdict:** keep the current Gemmamonster architecture. Do not replace it wholesale with vLLM ParserEngine, SGLang detectors, or llama.cpp PEG plumbing. Port only semantic fixes and add differential/conformance tests around the existing OVMS-native state machine.

## 2. Canonical Gemma 4 protocol

Primary references:

- Google prompt formatting: https://ai.google.dev/gemma/docs/core/prompt-formatting-gemma4
- Google function calling guide: https://ai.google.dev/gemma/docs/capabilities/text/function-calling-gemma4
- Canonical model template example: https://huggingface.co/google/gemma-4-31B-it/blob/main/chat_template.jinja

Google documents the tool lifecycle with six special tokens:

- `<|tool>` / `<tool|>` for declarations;
- `<|tool_call>` / `<tool_call|>` for model tool requests;
- `<|tool_response>` / `<tool_response|>` for tool results;
- `<|channel>` / `<channel|>` for reasoning channels;
- `<|"|>` as the native structured-string delimiter.

The canonical tool-call shape is conceptually:

```text
<|channel>thought
...reasoning...
<channel|><|tool_call>call:function_name{key:<|"|>value<|"|>,count:42}<tool_call|>
```

The important implementation consequence is that Gemma 4 tool arguments are **not ordinary JSON on the model wire**. The serving layer must parse the Gemma native representation and expose ordinary OpenAI-compatible `tool_calls[].function.arguments` JSON to clients.

The current Google templates also preserve assistant reasoning (`reasoning` / `reasoning_content`) on tool-call turns and serialize assistant tool calls back into Gemma's native format. This makes replay correctness part of the protocol, not merely output parsing.

**VERIFIED:** the latest Gemmamonster branch explicitly aligns its comment/contract with canonical close-before-tool ordering in commit `52c6b534dab9cb413eb175541870785cdd2c3`.

## 3. Comparative matrix

| Area | Google canonical | vLLM | SGLang | llama.cpp | Gemmamonster verdict |
|---|---|---|---|---|---|
| Prompt authority | Canonical template / Google docs | Uses dedicated Gemma 4 parser plus template | Dedicated detector/parser plus Gemma 4 deployment template | Specialized Gemma 4 chat path | Follow Google; peer runners are secondary evidence |
| Reasoning | `<|channel>thought\n...<channel|>` | Unified parser state machine | Separate reasoning/tool parser plumbing | PEG parser, `reasoning_content` support | Native `Gemma4ReasoningParser` on `BaseOutputParser` |
| Tool-call wire | `<|tool_call>call:name{...}<tool_call|>` | Native DSL -> OpenAI tool call | Native DSL -> OpenAI tool call | Native PEG tool rule | Native C++ parser -> `ToolCallDelta` |
| String delimiter | `<|"|>` | Explicit custom arg parser | Explicit custom arg parser | Explicit PEG rule | Explicit native value parser |
| Parallel calls | Canonical template can render multiple calls | Parser supports repeated calls; regressions exist | Supported, but index / `n>1` bugs recorded | PEG repeat respects `parallel_tool_calls` | Request policy preserved in 2026.5; must keep call indices independent |
| Tool-result replay | Canonical template contract | Template/parser integration | Template/server integration | Explicit `convert_tool_responses_gemma4` | Persistent session continuity + template overlay; keep golden replay tests |
| Streaming | Requires preserving control-token boundaries | Mature but repeatedly fixed | Detector buffers partial tokens; known token-stream bugs | PEG parser + grammar triggers | Phase-aware OVMS streamer; latest special-token handoff fix is load-bearing |
| Guided generation | Protocol does not prescribe engine | Structured output / grammar stack | Guided decoding stack | Native PEG + grammar trigger | `StructuredOutputConfig::Tag` with Gemma-native wrappers and JSON-schema content |
| Malformed native output | Application must validate before execution | Recovery behavior has expanded over time | Detector generally expects wrapped calls | Parser has dedicated recovery/scan behavior | Recovery allowed, but only registry-aware / prefix-bounded and never canonicalized as valid wire |

## 4. Gemmamonster implementation status and provenance

### 4.1 OVMS 2026.4 known-good line

The retained known-good anchor is:

```text
freeze/gemmamonster-2026.4-known-good
c48366fee1f10cdf6b5fe3c181522ed0c58fc9fd
```

Its immediate integration history includes `73419fca131afc7389e493cf3f2bbb7ef7ac8ec6` (`merge: integrate complete Gemma4 runtime and harness work`). The 2026.5 port later added an explicit migration-contract commit, proving that 2026.5 was treated as a forward port of the working 2026.4 behavior rather than a fresh implementation.

### 4.2 OVMS 2026.5 forward port

Key commits on the path to the current integration branch:

- `2d8df712cf8808d0718227c93bb12f40b8b720db` — `test(gemma4): port 2026.4 migration contracts onto 2026.5 baseline`
- `2eda5165d8d24393ae2cab4b63062ede3aedb266` — `feat(gemma4): forward-port hardened parser and guided generation to OVMS 2026.5`
- `2e52a839e337055d52cb7afe76e230657bf6c36d` — preserve hard tool policy and parallel request semantics
- `d6aa8c5b0daf0e057af33ac4a075a53a7438f4b0` — compose 2026.5 chat-template workarounds
- `6bd6ba3530ea36d8f0e00e9863059acd3423d722` — persistent session continuity
- `2d17e36f39412f18df558c49c6bc4661b833f675` — complete 2026.5 forward-port acceptance

The forward-port commit changes the production parser and generation-policy surface rather than adding an adapter on the outside. For guided tools it constructs native boundaries such as:

```text
begin = <|tool_call>call:<tool-name>
content = JSONSchema(tool.parameters)
end = <tool_call|>
```

It also makes hard tool policy fail closed instead of silently falling back to unguided generation. This is the correct semantic adaptation for OVMS because grammar ownership belongs in `GenerationConfigBuilder` / OpenVINO GenAI structured output, not in llama.cpp's PEG object model.

### 4.3 Reasoning parser semantic refit

The strongest provenance evidence is commit:

- `f9526c3e8aa96e1f49630a8dc6079479a919e91f` — `refactor(gemma4): make reasoning parser model-native`

It replaces inheritance from `Qwen3ReasoningParser` with direct inheritance from `BaseOutputParser` and defines Gemma-specific parsing configuration:

- start: `<|channel>thought\n`
- token-visible start: `<|channel>`
- end: `<channel|>`
- special tokens required
- an explicitly configured recovery boundary when a tool opener terminates an unclosed reasoning phase.

Related commits harden the semantic boundary:

- `4ed71ef084e8be04095f36aa6bc8ec5166df6b8e` — parse thought channel without Qwen inheritance
- `e106b214ba0d6c44640c77caa47dfeefde694389` — model tool start as reasoning boundary
- `52aee8bfe0cb76c68c79708a14009d9a69799e11` — hand off tool opener from reasoning phase
- `5038a8322762e25af65b553913af22afbe5c27c6` — post-tool reasoning boundary split tests

`df73eef690bbd2361b2d9d25a5695a50a43a4e92` drives the parser across the semantic boundary in a regression test and asserts a real `ToolCallDelta`, not merely token recognition.

**VERDICT:** this is a semantic refit of the vLLM-style Gemma behavior into OVMS. The behavior lineage is useful; the architecture is intentionally OVMS-native.

### 4.4 Current production parser surface

At the pre-document 2026.5 baseline, the dedicated source surface is:

```text
src/llm/io_processing/gemma4/gemma4_reasoning_parser.cpp
src/llm/io_processing/gemma4/gemma4_reasoning_parser.hpp
src/llm/io_processing/gemma4/gemma4_tool_parser.cpp
src/llm/io_processing/gemma4/gemma4_tool_parser.hpp
```

The tool parser has moved beyond the earlier ad-hoc object/array conversion approach. The 2026.5 forward port includes brace-aware nested parsing, native string delimiters, lossless numeric normalization, tool-name validation, bounded recovery, and request-registry awareness.

The latest hardening line adds two particularly important protections:

- `45ea4a8da56efdaccff11273cb286bbd6f52c3b6` — preserve special-token boundaries across reasoning -> tool phase handoff in `OVMSTextStreamer`;
- `7a13bc83bb349781e2f942b7bc644cebe07fb114` — make the protocol runner explicitly cover parser, generation grammar, prompt-state generation, Google-template overlay, and parallel-tool policy contracts.

The branch also narrows bare `call:` recovery to allowed native prefixes derived from the request tool registry. This is preferable to treating arbitrary prose containing `call:` as executable syntax.

## 5. vLLM dossier

Primary implementation:

- https://github.com/vllm-project/vllm/blob/main/vllm/parser/gemma4.py

Current vLLM uses a **unified ParserEngine state machine** for reasoning and tool calls. Its transitions explicitly cover:

- content -> reasoning on `<|channel>`;
- reasoning -> content on `<channel|>`;
- reasoning -> tool preamble on `<|tool_call>`;
- content -> tool preamble on `<|tool_call>`;
- `call:` -> tool name;
- `{` / `(` -> tool args;
- `<tool_call|>` -> content;
- back-to-back tool calls;
- prompt-tail detection for an already-open reasoning channel.

Its argument parser handles nested objects/arrays and `<|"|>` delimiters, and current code contains explicit partial-delimiter and partial-decimal protections for streaming.

This implementation is valuable as a semantic reference because it has accumulated real failure evidence. It should **not** be copied as a framework object into OVMS.

Important known failures / fixes:

- https://github.com/vllm-project/vllm/issues/44715 — quoted dictionary keys leaked `<|"|>` delimiters; reproduced on vLLM 0.19.1 and 0.22.1.
- https://github.com/vllm-project/vllm/issues/44522 — raw Gemma structural delimiters leaked during streaming.
- https://github.com/vllm-project/vllm/issues/54256 — reported 2026-08-28: a bare `call:` immediately after reasoning close can fall through a state-machine gap. Regardless of whether that model output is canonical, it is a useful recovery regression.
- Related recent work cited by #54256 includes PRs #53444, #53765 and #50015 around malformed/bare openers, required tool choice and prompt-seeded parsing.

**Lesson for Gemmamonster:** retain canonical Google transitions as the strict path, and keep malformed/bare behavior isolated as guarded recovery. Preserve streaming prefix fragments until they are unambiguous.

## 6. SGLang dossier

Primary tool detector:

- https://github.com/sgl-project/sglang/blob/main/python/sglang/srt/function_call/gemma4_detector.py

SGLang independently implements the same native DSL: `<|tool_call>`, `<tool_call|>`, `<|"|>`, nested object/array parsing, typed booleans/numbers, brace matching, and an incremental buffer that holds partial control-token prefixes.

That independent implementation confirms the important semantics, but its issue history also demonstrates why protocol correctness is more than detecting delimiters.

Known failures with concrete environments:

- https://github.com/sgl-project/sglang/issues/30556 — SGLang 0.5.14, `google/gemma-4-31B-it`, one NVIDIA GB200, TP=1: reasoning-aware `tool_choice=required` works for `n=1` but fails for `n>1`, placing guided tool JSON into reasoning content and returning no tool call.
- https://github.com/sgl-project/sglang/issues/25073 — repeated calls to the same function reused the tool's registry index instead of the assistant call index, causing OpenAI streaming clients to merge distinct calls.
- https://github.com/sgl-project/sglang/issues/35564 — token-by-token streaming failures include the Gemma 4 parser among affected detectors.

The SGLang Gemma 4 cookbook has also carried version-specific Transformers requirements and hardware recipes for H200, B200/B300 and MI300X-class deployments. Those are deployment evidence, not parser-contract authority.

**Lesson for Gemmamonster:** parser state must be per choice, tool-call indices must be per emitted call rather than per tool definition, and empty/simple argument objects need token-by-token tests.

## 7. llama.cpp dossier

Primary specialized implementation:

- https://github.com/ggml-org/llama.cpp/blob/master/common/parsers/gemma4.cpp

llama.cpp does not treat Gemma 4 as a generic Jinja-only case. `common_chat_params_init_gemma4()` builds a dedicated PEG parser, preserves Gemma special tokens, supports thinking extraction, creates a native Gemma value grammar, emits a tool grammar trigger on `<|tool_call>`, and respects `parallel_tool_calls` in the repeated tool-call rule.

It also has an explicit `convert_tool_responses_gemma4()` transformation. This collects an OpenAI-style sequence of assistant tool calls + `role: tool` results and rebuilds the Gemma template representation, preserving `reasoning_content` when present. This is especially relevant to Gemmamonster's generator/replay path.

The implementation contains a crucial limitation directly in source: the native Gemma argument grammar is not simply generated from ordinary JSON Schema because Gemma's wire representation is not JSON. llama.cpp therefore uses Gemma-native structural rules around values while still resolving schemas for grammar construction.

Concrete parser history/failure:

- llama.cpp PR #21418 introduced the specialized parser; issue https://github.com/ggml-org/llama.cpp/issues/22371 identifies first bad commit `b8635075f` for a content-truncation bug caused by treating literal `<|tool_call>` as a delimiter too eagerly.
- The issue demonstrates a general rule: delimiter recognition must match the full semantic prefix where possible, otherwise ordinary content mentioning a control token can be truncated.

**Lesson for Gemmamonster:** llama.cpp is the strongest independent reference for native generation/replay semantics. Its PEG implementation should not be transplanted, because OVMS already owns structured output through OpenVINO GenAI. The transferable parts are the Gemma-native wrapper grammar, replay normalization, parallel-call semantics, and negative tests for false delimiter triggers.

## 8. Transformers role

Transformers is useful in two ways:

1. It carries Gemma 4 model/template support used by Google examples and by downstream runners.
2. vLLM's Gemma utility lineage explicitly references Transformers Gemma 4 utilities.

It is not, by itself, the OpenAI serving contract. The canonical Google template plus serving-layer translation still determines how `assistant.tool_calls`, reasoning content, and tool responses are rendered into the native prompt.

Use Transformers as a parser/template oracle only when pinned to a specific model/template revision. Do not make behavior depend on whatever latest installed Transformers happens to render on a deployment host.

## 9. Known failure classes that must remain in the Gemmamonster test matrix

The peer implementations converge on the same classes of bugs:

1. **Split control tokens**: every byte/token split of `<|channel>`, `<channel|>`, `<|tool_call>`, `<tool_call|>` and `<|"|>` must be safe.
2. **Reasoning -> tool handoff**: canonical close-before-tool plus recovery for an omitted close or malformed/bare opener.
3. **False-positive tool starts**: ordinary content that mentions `<|tool_call>` or `call:` must not be truncated or executed.
4. **Nested arguments**: objects, arrays, empty objects, empty arrays, nested strings containing braces/commas.
5. **Typed bare scalars**: booleans, null, integers, negative values, decimals, large numbers without precision loss.
6. **Quoted keys / delimiters**: `<|"|>` must never leak into OpenAI JSON keys or values.
7. **Parallel/repeated calls**: repeated calls to the same function require distinct OpenAI call indices and IDs.
8. **Choice isolation**: `n>1` must not share parser state or grammar ownership across choices.
9. **Tool-result replay**: tool call -> result -> second call -> result -> final answer, with reasoning preserved only where the canonical template requires it.
10. **Prompt-tail state**: generation beginning inside an already-open reasoning channel must initialize correctly without inventing or leaking markers.
11. **Finish reasons**: `finish_reason=tool_calls` must imply at least one valid collected tool call; malformed output must not silently become executable.
12. **Long agent streams**: run OpenCode/CodeSleuth-style long prompts and incremental streams, not only synthetic 20-token examples.

## 10. Minimal delta plan from current Gemmamonster

### P0: freeze canonical protocol fixtures

Pin at least one current Google Gemma 4 canonical template revision and store golden rendered prompts for:

- no tools;
- one tool;
- multiple tools;
- one tool response;
- multiple tool responses;
- reasoning + call + response + second call;
- final assistant content after a tool loop.

The golden should be compared at the rendered-prompt boundary. The parser should not compensate for a broken serializer.

### P0: keep streamer boundary ownership explicit

Commit `45ea4a8...` demonstrates that parser correctness can still be defeated if `skip_special_tokens` changes before the next phase opener has been observed. Preserve this ordering contract and add split-boundary fuzzing around it.

### P0: harden recovery without broadening the language

The integration branch already moves in the right direction: bare-call recovery is registry-aware and limited to plausible native prefixes. Keep it a recovery path. Do not redefine bare `call:` as canonical Gemma 4 wire format merely because peer implementations tolerate it.

### P1: typed argument differential tests

Run the same native argument corpus through:

- Gemmamonster parser;
- current vLLM Gemma 4 parser;
- current SGLang Gemma 4 detector;
- llama.cpp PEG parser where the harness permits it.

Compare semantic JSON values, not byte-for-byte internal events. Any disagreement should become an explicit compatibility decision with a regression fixture.

### P1: parallel and repeated-call identity

Add tests where the model emits the same function three times. The OpenAI-visible calls must use call-local index/ID identity. This directly guards the SGLang #25073 class.

### P1: `n>1` / independent choice state

Even if the current OVMS API path does not expose every SGLang sampling mode, parser state objects must never be implicitly shared between choices or sessions. Encode the invariant in tests now rather than after the API surface grows.

### P2: upstream drift watch

Before promotion, compare the Gemmamonster implementation against current `openvinotoolkit/model_server` main. Upstream OVMS now exposes Gemma 4 parser-related surface as well, so future work should be a three-way reconciliation:

```text
Google canonical protocol
        +
current upstream OVMS implementation
        +
Gemmamonster known-good behavioral evidence
```

Do not automatically delete Gemmamonster code merely because an upstream class has the same name. Compare semantics and tests first.

## 11. Acceptance gate

Call Gemma 4 agentic support **complete for this integration line** only when all of the following are green on one pinned source SHA:

- parser unit suite;
- generation grammar / hard tool policy tests;
- canonical rendered-prompt golden tests;
- reasoning/tool phase-boundary streaming splits;
- single and parallel tool calls;
- repeated same-function calls;
- multi-turn tool-result replay;
- `reasoning_content` replay;
- malformed-output fail-safe tests;
- long OpenCode/CodeSleuth-style agent loop acceptance;
- one real Gemma 4 runtime lane with model, hardware, OVMS/OpenVINO versions recorded.

The current runner expansion in `7a13bc83...` is a good basis because it makes parser, grammar, prompt-state, template overlay and parallel-tool policy explicit targets rather than allowing an incomplete green run.

## 12. Source/provenance note

The user-provided local path:

```text
C:\git\gemma4-44-knowngood\docs\gemma4\upstream-tool-calling-technical-case-draft.md
```

was not present in the inspected 2026.5 integration tree or the inspected repository documentation branch under the same repository-relative path. It is therefore **not used as verified evidence in this verdict**. Its claims should be reconciled later if that local draft is committed or otherwise made available. No conclusions above depend on inventing its contents.

## 13. Final verdict

**KEEP AND HARDEN the existing Gemmamonster implementation.**

The current code has crossed the important architectural threshold: Gemma 4 is represented as a first-class model protocol inside OVMS rather than as a Qwen-shaped parser with token substitutions. Guided generation, request policy, reasoning, tool parsing, prompt adaptation and streaming are already joined into one serving path.

The comparative evidence does not justify another rewrite. It justifies a stricter compatibility perimeter:

- Google defines the canonical protocol;
- vLLM supplies high-value state-machine and streaming failure evidence;
- SGLang supplies independent detector and parallel/choice failure evidence;
- llama.cpp supplies the strongest native generation/replay reference;
- Transformers supplies pinned template/parser utilities;
- Gemmamonster keeps the implementation in OVMS-native abstractions and imports only the semantics that survive conformance testing.

That is the architecture to promote.