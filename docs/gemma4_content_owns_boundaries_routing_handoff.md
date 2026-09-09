# Gemma4 CONTENT ownsToolCallBoundaries routing handoff

## Exact base SHAs

| Role | SHA | Ref / note |
|------|-----|------------|
| **Reproduction base (this fix)** | `afbf5073baa02f79c4c385aec61f78ce193f84ee` | `fix/gemma4-native-tool-calling-upstream-v2` after `ownsToolCallBoundaries` wiring + `parallelToolCalls`. RED contracts fail here. |
| **Historical OVMS 2026.4 reliability HEAD** | `2cb5a9a0e8d22732de2d1c89f52795c2de612a57` | Live adversarial/reliability campaign binary lineage (2026.4). Not the compile base of this branch; cited because that is the 2026.4 SHA where tool-call regressions were first measured. |
| **Frozen 2026.4 known-good package tip** | `c48366fee1f10cdf6b5fe3c181522ed0c58fc9fd` | `origin/freeze/gemmamonster-2026.4-known-good` |

Branch: `fix/gemma4-content-owns-boundaries-routing`

## Commits

1. **RED** `fbd9cda22` — `test(gemma4): RED content ownsToolCallBoundaries routing contracts`
2. **GREEN** (this tip) — `fix(gemma4): route CONTENT through owning tool parser + drain loop`

## Affected files

- `src/llm/io_processing/output_parser.cpp` — CONTENT phase routes to tool parser when `ownsToolCallBoundaries`
- `src/llm/io_processing/gemma4/gemma4_tool_parser.cpp` — drain loop so `{}` / Content→ToolCallStarted does not stall
- `src/test/llm/output_parsers/gemma4_content_owns_routing_contract_test.cpp` — RED/GREEN contracts
- `src/test/llm/output_parsers/gemma4_output_parser_test.cpp` — fail-closed streaming expectations (complete call, no early name header)

## Regression (before GREEN)

With `ownsToolCallBoundaries=true`, generic CONTENT only matched `<|tool_call>` startTags and always called `contentParser`. After the first UNKNOWN→CONTENT prose flush:

- later `call:` / tool bytes were appended via `contentParser` again → **tool drop** into content
- OR, if forced through tool parser without a drain loop, Content→ToolCallStarted returned `false` and stopped the loop → **stall** on empty `{}`

## Trace contract (same chunk sequence, before vs after)

Notation:
- `phase` = OutputParser processing phase
- `cache` = `streamOutputCache` buffer
- `contentParser in` / `toolParser in` = which sub-parser received the chunk text
- `tool.streamingContent` = Gemma4ToolParser internal buffer after the call

### Scenario A — UNKNOWN → CONTENT

| step | chunk | phase before | cache before | contentParser | toolParser | phase after | cache after | tool.streamingContent |
|------|-------|--------------|--------------|---------------|------------|-------------|-------------|------------------------|
| 1 | `HELLO` | UNKNOWN | `` | **yes** (`HELLO`) | no | CONTENT | cleared | unchanged/empty |

**Before fix:** same. **After fix:** same (first prose still uses contentParser).

### Scenario B — several consecutive CONTENT chunks

| step | chunk | phase before | contentParser | toolParser | downstream |
|------|-------|--------------|---------------|------------|------------|
| 1 | `A` | UNKNOWN→CONTENT | yes | no | `A` |
| 2 | `B` | CONTENT | **before:** yes / **after:** toolParser | **after:** yes | `B` |
| 3 | `C` | CONTENT | before: yes / after: toolParser | after: yes | `C` |

**Invariant after fix:** concatenated downstream `ABC…` equals input prose; each chunk appears once (no duplicate `A`/`B`).

### Scenario C — CONTENT → `<|tool_call>`

| step | chunk | phase before | contentParser | toolParser | phase after | note |
|------|-------|--------------|---------------|------------|-------------|------|
| 1 | `PREFIX` | UNKNOWN | yes | no | CONTENT | prose |
| 2 | `<|tool_call>` | CONTENT | **before: yes (leak)** / **after: no** | **after: yes** | TOOL_CALLS_PROCESSING_TOOL | hold / no content leak |
| 3 | `call:sort{array:[7]}` | TOOL… | no | yes | TOOL… | validated call |
| 4 | STOP/`<tool_call|>` | TOOL… | no | yes | TOOL… | complete delta |

### Scenario D — StreamingContentWithTurnToken (`<turn|>` strip)

Chunks: `This is` → ` some content` → ` with a turn token at the end.` → `<turn|>`+STOP

**After fix:** toolParser owns CONTENT path; `<turn|>` erased via `stringsToErase` / tool parser tag erase; downstream text has no `<turn|>`; no duplicate prose.

### Scenario E — HolisticStreaming (fail-closed)

Early name headers at `{…` are **not** emitted. One complete `ToolCallDelta{id,name,arguments}` is published when the argument container closes. Second call likewise. Trailing content after `<tool_call|>` emitted once.

### Scenario F — once-only byte accounting

For input `HELLO_WORLD` + tool call args `{"array":[1]}`:

- `HELLO_WORLD` appears once in content deltas
- tool name `sort` and args once in tool deltas
- structural tags `<|tool_call>` / `<tool_call|>` are not required downstream (consumed), but must not be re-injected as content

## How to re-run

```bat
bazel test //src:llm_output_parser_tests --test_filter=Gemma4ContentOwnsRouting*:Gemma4OutputParserTest.Streaming*:Gemma4V2ContractTest.Recovers*
```
