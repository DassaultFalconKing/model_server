# Gemma4 content-owned boundary routing port contract

**Date:** 2026-09-09  
**Target branch:** `integration/gemma4-parser-generator-refit-next`  
**Target RED commit:** `01307da75241abe36606a5f7474bf14c22817018`  
**Source branch:** `fix/gemma4-content-owns-boundaries-routing`  
**Source GREEN tip:** `b949d0837cae8201403592f0524563403d136bcc`  
**Source dofix tip:** `671f84c255ea41fd3431a02237cb0e3a0da52700`  
**Source RED commit:** `fbd9cda22466835317bfe1603e942f3269056f1f`  
**Source reproduction base:** `afbf5073baa02f79c4c385aec61f78ce193f84ee`

This is a port contract, not an authorization to overwrite the Gemmamonster parser with an older file revision. Gemma4 parser work in this repository is cumulative: parsers grow by preserving existing hardening seams and adding only the missing behavior proven by a RED test.

## 1. Problem being ported

After `ownsToolCallBoundaries=true`, Gemma4 framing must remain owned by `Gemma4ToolParser` after ordinary CONTENT has started. The generic content parser cannot safely own later chunks because it does not know Gemma4 native framing:

- `<|tool_call>` / `<tool_call|>`;
- native `call:<tool>{...}` and `call:<tool>(...)` syntax;
- bounded bare `call:` recovery;
- `<turn|>` erasure;
- `<|tool_response>` erasure;
- in-chunk transitions such as `call:empty_params{}`.

The source handoff demonstrated the failure pattern:

1. first `UNKNOWN -> CONTENT` prose chunk is correctly emitted through the content parser;
2. later CONTENT chunks keep going through the generic content parser;
3. a later Gemma4 tool opener can leak as content or be dropped;
4. if the route is naively switched to the tool parser without draining state transitions, `{}` can stall because one chunk can advance more than one parser state.

## 2. Exact semantic transfer

Only these production behaviors are authorized for the target branch.

### 2.1 `src/llm/io_processing/output_parser.cpp`

In the `CONTENT` phase, when `applyToolParser` is true and the selected tool parser advertises `ownsToolCallBoundaries`, route the accumulated `streamOutputCache` through `parseToolCallChunk(tokens, finishReason)` immediately.

Required shape:

```cpp
if (toolParser->getParsingConfig().ownsToolCallBoundaries)
    return parseToolCallChunk(tokens, finishReason);
```

This preserves the existing double-buffering contract:

- `OutputParser::streamOutputCache` owns only the current outer chunk accumulation until it is handed to a sub-parser;
- `Gemma4ToolParser::streamingContent` owns Gemma4 framing state and the unconsumed suffix after handoff;
- clearing `streamOutputCache` inside `parseToolCallChunk()` is still required to avoid duplicate delivery.

Do not remove the outer cache clear merely because the tool parser has its own buffer. That is not simplification; that is byte duplication wearing a fake moustache.

### 2.2 `src/llm/io_processing/gemma4/gemma4_tool_parser.cpp`

In `Gemma4ToolParser::parseChunk()`, replace the single-step `if (parseNewContent()) { ... }` publication path with a drain loop that continues while the internal state machine advances without emitting a delta.

The loop must handle at least:

- `Content -> ToolCallStarted` in the same call;
- `ToolCallStarted -> ToolCallParameters`;
- `ToolCallParameters -> ToolCallEnded`;
- `ToolCallEnded -> AfterToolCall`;
- `AfterToolCall -> Content`;
- complete empty-object calls such as `{}`;
- finish-reason-triggered parameter parsing.

The loop must still emit only one `Delta` per `parseChunk()` invocation. It may continue internally until it either emits a complete validated call/content delta or reaches a stable waiting state.

### 2.3 Dofix from `671f84c25`

The second source fix extended the routing work after tests exposed split bare-call boundaries under streamer chunking (`call` + `:` with `DELAY_N_TOKENS=3`). The semantic transfer is:

- hold trailing fragments that can still become `<|tool_call>` or a line-start `call:` boundary;
- flush held ordinary bytes on STOP;
- when a bare line-start `call:` resolves to an unknown tool, rewind to the bare-call start and re-emit as content;
- keep anchored `<|tool_call>call:unknown{...}` fail-closed / dropped;
- avoid a drain-loop spin when STOP reaches `ToolCallEnded` with no publishable call.

On the target branch this must additionally preserve the newer full-prefix/literal-marker protection: once `OutputParser` routes CONTENT through `Gemma4ToolParser`, the tool parser itself must not treat ordinary text containing `<|tool_call>` as an anchored tool call unless the marker is at least followed by a `call:` suffix or a still-possible `call:` prefix.

## 3. What must not be overwritten

The target branch already contains newer hardening work than the source branch. A raw file replacement from `b949d0837...` or `671f84c25...` would regress those changes.

Do not overwrite or weaken:

- registry-aware viable-prefix bare-call recovery, including `call:quest` followed by `ion{...}`;
- rejection of impossible bare prose such as `call:question prose`;
- full native-prefix text start tags that prevent literal `<|tool_call>` content truncation;
- internal anchored-boundary validation after CONTENT is routed through `Gemma4ToolParser`;
- separate `tokenIdStartTags` handling for streamer special-token phase seams;
- numeric lexeme validation that rejects malformed numbers such as `1.`, `1e`, `-`, and `01`;
- lexical preservation for valid large/high-precision numbers;
- fail-closed complete-call publication, where name and arguments are emitted together only after argument validation;
- malformed/truncated tool-call containment;
- unique call-local indices and IDs for repeated same-function calls.

## 4. Tests already ported to target

The RED test commit on the target branch is:

`01307da75241abe36606a5f7474bf14c22817018`

It adds:

`src/test/llm/output_parsers/gemma4_content_owns_routing_contract_test.cpp`

The test file is intentionally part of `//src:llm_output_parser_tests` through the existing glob in `src/BUILD`; no additional BUILD wiring is needed.

The core scenarios are:

- `UNKNOWN -> CONTENT -> TOOL` without dropped or duplicated ordinary bytes;
- consecutive CONTENT chunks emitted exactly once;
- CONTENT followed by `<|tool_call>` without leaking the opener as content;
- `<turn|>` stripped once in streaming content;
- empty `{}` arguments completing in one chunk.

The source dofix also depends on existing `Gemma4V2ContractTest.RecoversObservedBareCallAfterOrdinaryTextBoundary` and `Gemma4V2ContractTest.RecoversWhitespacePrefixedBareKnownCallWithoutEndMarker` staying green.

## 5. Target semantic port commits

The target branch intentionally split the port into reviewable pieces:

1. `7b0b1c8e23411602cf099b2428577343694297dd`  
   `fix(gemma4): track bare-call ownership during streaming`

2. `d2edab5e75f0a0458c8e81271a9751f4a7befa61`  
   `fix(gemma4): route content through owning tool parser`

3. `0949816f0b664dc9c2c05c5f232ed8e83ffc02a2`  
   `fix(gemma4): hold split bare-call boundaries`

4. `e53cc32d5b5f3db25ee311d3591416285a0f6a4f`  
   `fix(gemma4): preserve literal tool markers under content-owned routing`

These commits are a semantic port, not a source-file replacement. They preserve the target branch's stricter parser/generator history while transferring the source branch's routing and streamer-boundary findings.

## 6. Verification gate after GREEN

Minimum targeted command:

```bat
bazel test //src:llm_output_parser_tests --test_filter=Gemma4ContentOwnsRouting*:Gemma4OutputParserTest.Streaming*:Gemma4V2ContractTest.Recovers*
```

The source branch reported these local results at `671f84c25`:

- `//src:llm_output_parser_tests` builds cleanly;
- `//src/test/llm/generation_config:gemma4_generation_contract_test` builds cleanly;
- 61/61 Gemma4 parser tests green (`V2` 13, `OutputParser` 43, `ContentOwnsRouting` 5);
- 14/14 generation contracts green;
- remaining red tests in that binary were 12 `Devstral*` cases failing due missing `openvino_tokenizer.xml`, unrelated to touched files according to the source report.

Those source results do not certify the target branch. The target branch still needs a fresh run because it contains extra hardening and Jinja-contract commits.

This command is not a full release gate. It is only the routing regression gate before returning to the larger program:

1. Jinja contract;
2. streamer boundary matrix;
3. static final audit;
4. live tests.
