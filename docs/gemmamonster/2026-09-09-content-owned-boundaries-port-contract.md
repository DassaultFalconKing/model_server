# Gemma4 content-owned boundary routing port contract

**Date:** 2026-09-09  
**Target branch:** `integration/gemma4-parser-generator-refit-next`  
**Target RED commit:** `01307da75241abe36606a5f7474bf14c22817018`  
**Source branch:** `fix/gemma4-content-owns-boundaries-routing`  
**Source GREEN tip:** `b949d0837cae8201403592f0524563403d136bcc`  
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

## 3. What must not be overwritten

The target branch already contains newer hardening work than the source branch. A raw file replacement from `b949d0837...` would regress those changes.

Do not overwrite or weaken:

- registry-aware viable-prefix bare-call recovery, including `call:quest` followed by `ion{...}`;
- rejection of impossible bare prose such as `call:question prose`;
- full native-prefix text start tags that prevent literal `<|tool_call>` content truncation;
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

## 5. Expected next GREEN commit

The next GREEN commit on `integration/gemma4-parser-generator-refit-next` should change only:

- `src/llm/io_processing/output_parser.cpp`;
- `src/llm/io_processing/gemma4/gemma4_tool_parser.cpp`.

Commit message recommendation:

`fix(gemma4): route content through owning tool parser`

If the incoming "dofix" from the local agent changes the same two seams, reconcile it against this contract rather than stacking both fixes blindly. The winning version is the one that preserves the newer target-branch parser hardening and satisfies the RED routing contracts.

## 6. Verification gate after GREEN

Minimum targeted command:

```bat
bazel test //src:llm_output_parser_tests --test_filter=Gemma4ContentOwnsRouting*:Gemma4OutputParserTest.Streaming*:Gemma4V2ContractTest.Recovers*
```

This command is not a full release gate. It is only the routing regression gate before returning to the larger program:

1. Jinja contract;
2. streamer boundary matrix;
3. static final audit;
4. live tests.
