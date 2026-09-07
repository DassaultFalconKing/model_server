# GEMMAMONSTER Acceptance Matrix v1

Date: 2026-09-07
Status: CANONICAL ACCEPTANCE GATE
Scope: fork-main candidate carrying current Gemma4 parser + generator/tool-calling stack on fresh OVMS 2026.4 upstream.

## Purpose

This document defines the minimum evidence required before a Gemma4 integration candidate may be promoted to the GEMMAMONSTER fork `main`.

A candidate is not accepted because one unit target passed, a Python harness passed, or a previous binary behaved correctly. Acceptance is exact-head and layered: source contracts, focused C++ tests, Windows build, live OVMS runtime, streaming/tool-loop behavior, and provenance must agree.

## Status vocabulary

Every matrix cell is reported as exactly one of:

- `PASS`: the exact command/case ran against the exact candidate and met the stated invariant.
- `FAIL`: the case ran and violated the invariant.
- `BLOCKED`: execution could not reach the assertion/runtime contract because of a named environment, fixture, toolchain, dependency, or startup blocker.
- `NOT_RUN`: the case was not attempted.

`BLOCKED` and `NOT_RUN` are never aliases for `PASS`.

## Exact-head provenance gate

Before any result is accepted, record:

```text
FORK_MAIN_BASE_SHA
UPSTREAM_MAIN_SHA
CANDIDATE_BRANCH
CANDIDATE_SHA
MERGE_BASE_SHA
OVMS_BINARY_SHA256
OVMS_VERSION
OPENVINO_VERSION
OPENVINO_GENAI_VERSION
MODEL_PATH
MODEL_ID
MODEL_REVISION_OR_LOCAL_HASH
CHAT_TEMPLATE_REVISION
CHAT_TEMPLATE_SHA256
TOOL_PARSER
REASONING_PARSER
TARGET_DEVICE
LAUNCH_PROFILE
```

The running `ovms.exe` must be shown to come from the candidate source SHA or from a reproducible build whose provenance maps to it. Stale binaries invalidate live results.

## Canonical tool-choice semantics

The following semantics are normative for this gate.

| tool choice | `parallel_tool_calls` | Required behavior |
|---|---:|---|
| `none` | true/false | zero tool calls; no tool grammar active |
| `auto` | omitted/true | zero or more valid request-visible tool calls; direct prose remains legal |
| `auto` | false | zero or one valid request-visible tool call; direct prose remains legal |
| `required` | omitted/true | one or more valid request-visible tool calls; prose-only completion is illegal |
| `required` | false | exactly one valid request-visible tool call |
| named | omitted/true | one or more calls, all to the selected tool |
| named | false | exactly one call to the selected tool |

`parallel_tool_calls` defaults to `true` when omitted. A non-boolean value is an invalid OpenAI request.

For Gemma4 generation:

```text
parallel_tool_calls=true  -> stop_after_first=false
parallel_tool_calls=false -> stop_after_first=true
```

`auto` uses a triggered/lazy structural tool region: free generation before `<|tool_call>`, constrained native tool syntax after the trigger, and free generation again after a completed tag when parallel calls are permitted.

`required` and named choices use mandatory structural tool generation and remain fail-closed if structured-output validation fails.

## Gate A: source and API contracts

| ID | Case | Expected |
|---|---|---|
| A01 | no tools / ordinary chat | no structured tool config |
| A02 | `tool_choice=none` with tools present | no structured tool config |
| A03 | `auto` with tools | Gemma4 lazy/triggered tool structure, `at_least_one=false` |
| A04 | `required` with tools | mandatory Gemma4 tool structure, `at_least_one=true` |
| A05 | named tool | only selected tool is legal |
| A06 | unavailable named tool | `InvalidArgument` |
| A07 | `required` or named with empty tools | `InvalidArgument` |
| A08 | `parallel_tool_calls` absent | request state is `true` |
| A09 | `parallel_tool_calls=true` | request state true, `stop_after_first=false` |
| A10 | `parallel_tool_calls=false` | request state false, `stop_after_first=true` |
| A11 | non-boolean `parallel_tool_calls` | `InvalidArgument` |
| A12 | Responses API serialization | emits actual request policy, not hard-coded `true` |
| A13 | Gemma hard-choice validation fallback | structured output preserved / request fails closed |
| A14 | non-Gemma builder validation fallback | historical generic behavior preserved; Gemma policy does not leak |
| A15 | active Gemma tool grammar + conflicting response-format grammar | rejected rather than silently overwritten |

Focused tests expected to cover this gate include the Gemma generation contract and OpenAI parallel-tool-call contract targets.

## Gate B: parser deterministic contracts

These cases are exercised against the exact candidate parser in unary and, where meaningful, streaming form.

| ID | Input family | Expected |
|---|---|---|
| B01 | canonical `<|tool_call>call:name{...}<tool_call|>` | one correct tool call |
| B02 | nested objects and arrays | recursive structure preserved |
| B03 | null/bool/int/float scalars | JSON scalar type preserved |
| B04 | Gemma native `<|\"|>...<|\"|>` strings | correct JSON string |
| B05 | braces/commas/JSON-like text inside string | no structural mis-scan |
| B06 | Windows paths and backslashes | byte/escape fidelity after JSON serialization |
| B07 | parenthesized anchored arguments, when compatibility path is enabled | valid call without teaching generator to emit variant |
| B08 | anchored colon-name compatibility form | parsed only at valid tool boundary |
| B09 | reasoning followed by accepted direct tool preamble | reasoning preserved, tool call parsed |
| B10 | unknown tool name | never executable as request-visible tool |
| B11 | malformed numeric-looking scalar | never emitted as invalid JSON RawValue |
| B12 | incomplete bare-call prose at EOF | prose preserved; not silently swallowed |
| B13 | fragmented real bare call | recoverable when structural argument container arrives later |
| B14 | truncated malformed call | no invented/synthetic structure unless explicitly specified by contract |
| B15 | multiple canonical calls | ordering/indexing preserved |

## Gate C: streaming invariants

Streaming must be semantically equivalent to unary parsing for complete output.

| ID | Case | Expected |
|---|---|---|
| C01 | split `<|tool_call>` start marker across chunks | no marker fragment leaks into content |
| C02 | split `<tool_call|>` end marker across chunks | no marker fragment leaks; call closes once |
| C03 | split function name | exact name reconstructed |
| C04 | split native string delimiter | no premature structural transition |
| C05 | split escape/backslash sequence | arguments remain valid and equal to unary result |
| C06 | split nested object/array boundaries | same final arguments as unary |
| C07 | multi-call stream | monotonic tool indices and correct per-call accumulation |
| C08 | `parallel_tool_calls=false` | no second tool-call delta may appear |
| C09 | generation ends during ordinary prose resembling `call:` | prose not promoted into executable tool call |
| C10 | generation ends after incomplete tool-looking prefix | fail safely; no delimiter debris in assistant content |

For the canonical regression corpus, transport chunking should cover meaningful boundary positions rather than only one convenient split.

## Gate D: live tool-choice matrix on patched OVMS

Run against the target Gemma4 deployment, currently the GEMMAMONSTER Wondernuttz/Heretic 26B lane unless superseded by a recorded model.

| ID | Request | Expected |
|---|---|---|
| D01 | `none`, tool-like user request | zero tool calls |
| D02 | `auto`, greeting/no-tool task, parallel=true | prose-only legal |
| D03 | `auto`, natural single-tool task, parallel=true | valid request-visible call or justified prose; no malformed tool structure |
| D04 | `auto`, natural two-tool task, parallel=true | multiple calls permitted |
| D05 | `auto`, natural two-tool task, parallel=false | at most one call |
| D06 | `required`, unnatural tool request, parallel=true | at least one tool call; never prose-only |
| D07 | `required`, two-tool pressure, parallel=false | exactly one valid tool call |
| D08 | named choice with two tools, parallel=true | only selected name emitted |
| D09 | named choice, parallel=false | exactly one selected-tool call |
| D10 | nested OpenCode-style `question` schema | valid recursively structured arguments |
| D11 | enum/schema pressure after entering tool trigger | emitted arguments remain inside declared schema |
| D12 | Windows path argument task | path survives parser/JSON round trip |

For `auto`, a supported canonical schema that causes structured-output validation to be dropped/fallen back is an acceptance failure for the guided-auto lane, even if the request subsequently produces readable prose.

## Gate E: reasoning interaction

| ID | Case | Expected |
|---|---|---|
| E01 | `auto`, thinking enabled, no-tool task | reasoning may occur; prose-only completion remains legal |
| E02 | `auto`, thinking enabled, tool task | reasoning may precede triggered tool call |
| E03 | `required`, thinking enabled | optional reasoning followed by mandatory tool call |
| E04 | named, thinking enabled | optional reasoning followed only by selected tool |
| E05 | reasoning content containing tool-like prose | parser does not execute unanchored fake call text |

## Gate F: tool-result chain and agent loop

| ID | Case | Expected |
|---|---|---|
| F01 | assistant tool call -> tool response -> assistant prose | chain continues without protocol corruption |
| F02 | assistant tool call -> tool response -> second tool call | second turn honors request/tool policy |
| F03 | chained `parallel_tool_calls=false` | next assistant turn still cannot emit a second call in that turn |
| F04 | restart/resume where supported by deployment harness | no stale parser/session state leaks between requests |
| F05 | OpenCode real `question` interaction | correct tool selection and parse under real client request shape |
| F06 | NovaClaw fragmented streaming interaction | no premature stop or malformed partial tool delta caused by parser boundary handling |

## Gate G: negative/security corpus

| ID | Case | Expected |
|---|---|---|
| G01 | ordinary prose containing fake SHA/tool-looking text | no structured call |
| G02 | unknown function name in model output | rejected/not executable |
| G03 | malformed JSON/native scalar | no invalid response JSON emitted |
| G04 | conflicting multiple tool markers | fail safely; no cross-call argument contamination |
| G05 | string payload containing delimiter-like text | remains string data unless a real parser-owned boundary is reached |
| G06 | unavailable named request choice | API error before generation |
| G07 | non-boolean parallel policy | API error before generation |

## Gate H: Windows build and focused C++ tests

Before live acceptance:

1. Windows/Bazel environment preflight must resolve Bazel, MSYS bash, MSVC, Python, OpenVINO, OpenCV and required tokenizer fixture.
2. The exact candidate must compile.
3. Focused C++ targets must run from Bazel rather than only as manually invoked binaries, unless a documented Bazel sandbox/DLL blocker remains, in which case status is `BLOCKED`.

Required focused targets, subject to the candidate's final BUILD layout:

```text
//src/test/llm/generation_config:gemma4_generation_contract_test
//src/test/llm/generation_config:openai_parallel_tool_calls_contract_test
//src/test/llm/gemma4_fast:gemma4_parser_contract_test
//src/test:kfs_rest_test
//src/test/llm:max_model_length_test
```

The final integration implementation may add or rename a focused target; the report must map each invariant above to the actual executed target.

## Gate I: performance evidence

Performance evidence is mandatory to record but v1 does not invent an arbitrary rejection threshold before a baseline exists.

For a stable toolbox and fixed model/profile, record at minimum:

```text
no-tools baseline TTFT
auto/no-call TTFT
auto/tool-call TTFT
required TTFT
named TTFT
parallel=true TTFT
parallel=false TTFT
decode tok/s
wall tok/s
structured-output/xgrammar initialization or compile time, if observable
```

Do not add a grammar cache merely because grammar compilation exists. A cache becomes an optimization candidate only if measured compiler/initialization cost is materially visible in end-to-end TTFT or request throughput.

## Final promotion gate

A candidate may be proposed for fork `main` only when:

- source/API contract gates are PASS;
- focused parser/generator C++ contracts are PASS;
- Windows candidate build is PASS;
- live `none/auto/required/named` matrix is PASS;
- both `parallel_tool_calls=true` and `false` are evidenced;
- streaming boundary cases are PASS;
- at least one real OpenCode tool interaction is PASS;
- NovaClaw streaming/tool-loop acceptance is PASS or explicitly separated as an external-client blocker with OVMS raw behavior proven correct;
- exact source/binary/template/model provenance is attached;
- no unresolved parser/generator regression is hidden behind a Python-harness substitute.

## Acceptance report skeleton

```text
GEMMAMONSTER_ACCEPTANCE_REPORT

SOURCE_SHA:
BINARY_SHA256:
UPSTREAM_BASE:
MODEL:
TEMPLATE_REVISION:

SOURCE_CONTRACTS: PASS|FAIL|BLOCKED
CPP_FOCUSED_TESTS: PASS|FAIL|BLOCKED
WINDOWS_BUILD: PASS|FAIL|BLOCKED
LIVE_TOOL_CHOICE_MATRIX: PASS|FAIL|BLOCKED|NOT_RUN
PARALLEL_POLICY: PASS|FAIL|BLOCKED|NOT_RUN
STREAMING: PASS|FAIL|BLOCKED|NOT_RUN
CHAINED_TOOL_LOOP: PASS|FAIL|BLOCKED|NOT_RUN
OPENCODE_DOGFOOD: PASS|FAIL|BLOCKED|NOT_RUN
NOVACLAW_DOGFOOD: PASS|FAIL|BLOCKED|NOT_RUN
PERFORMANCE_EVIDENCE: RECORDED|NOT_RECORDED

BLOCKERS:
- ...

OVERALL:
ACCEPTED
or
NOT_ACCEPTED
```
