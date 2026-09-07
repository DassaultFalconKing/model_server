# Gemma4 Local Acceptance Integration Gate Design

## Status

Approved design for the pre-maintainer integration gate.

## Goal

Produce one exact, reproducible, locally testable OVMS ref that combines the best currently proven Gemma4 parser hardening, generation-policy behavior, OpenAI API policy fidelity, streaming/session semantics, and acceptance evidence. A local full PASS on the target Gemma4 machine promotes that exact ref to `MAINTAINER_PR_SOURCE` and becomes the evidence basis for splitting minimal upstream-friendly Maintainer PRs.

## Pinned inputs

At design freeze time:

- Upstream `openvinotoolkit/model_server` `main`: `a114cfa8ed64e72337a83f55a018c1f8b0c65f0b`.
- Integration spine candidate: `fix/gemma4-responses-parallel-tool-policy` at `34c2f23d58e96a2c2ef1b3e2f940909c3131ace5`.
- Parser hardening source: `fix/gemma4-parser-hardening-post-f36d2d75` at `d1c21ac1a54d499e644e7619155944a3875fd071`.
- Common branch point for the recent parser and generator work: `f36d2d758264ac5f371c344c49e485f582b07b5a`.
- Previously proven live required/chained-session evidence source: exact tested commit `81ff2f2cae8b79cc22f7103cf4c29eb1953f9789`.

All refs MUST be re-resolved immediately before implementation. Any movement requires re-evaluation rather than silently using a new head.

## Integration strategy

Use `fix/gemma4-responses-parallel-tool-policy` as the integration spine and selectively replay the parser-hardening delta from the parser branch. Do not merge the entire historical set of Gemma4 branches. Do not mechanically merge `fix/gemma4-opencode-auto-tool-native`; its intended behavior must instead be checked against the newer lazy-auto implementation already present on the integration spine.

The implementation ref will be:

`integration/gemma4-local-acceptance-2026.4`

The ref starts from the exact re-resolved integration-spine SHA, not from fork `main` and not from upstream `main`.

## Feature contracts

### F1. Parser language

The integrated parser must preserve the hardened native Gemma4 tool-call contract:

- tagged native tool calls;
- bounded bare `call:` recovery only where explicitly allowed;
- recursive object and array values;
- exact/lossless numeric spelling through parse and re-emission;
- faithful string and Windows-path escaping;
- request-scoped allowed-tool registry validation;
- malformed or unavailable calls fail closed rather than becoming executable tool calls;
- malformed tool payloads are bounded by the tool-call end marker and cannot swallow arbitrary trailing prose.

The parser-hardening replay must retain the recent regression contracts covering lossless-number validation, bounded bare-call recovery, Windows-path argument fidelity, fail-closed parser output invariants, and separation of runtime provenance from grounding fixtures.

### F2. Generation controller

Gemma4 tool selection must have distinct semantics:

- `tool_choice=none`: tool generation is prohibited.
- `tool_choice=required`: at least one valid tool call is required; there is no legal zero-tool terminal branch.
- named tool choice: only the named tool and its schema are legal, and a call is mandatory.
- `tool_choice=auto`: ordinary prose remains legal; tool schema/grammar becomes authoritative only when generation enters the tool branch. This is the intended lazy-capable behavior and must be classified by tests as `IMPLEMENTED`, `PARTIALLY_IMPLEMENTED`, or `BLOCKED_BY_PLATFORM`.
- hard-choice setup or grammar failures fail closed.
- empty `ConstString("")` MUST NOT be used because xgrammar rejects it.

### F3. Streaming semantics

Streaming must preserve parser state across chunks and prove:

- split tool tags;
- split argument objects and nested containers;
- incomplete calls never become executable calls;
- prose preceding or following an incomplete tool call is not silently discarded;
- multi-call progression produces stable tool-call deltas and does not merge distinct calls.

A non-streaming live PASS is not evidence of streaming PASS.

### F4. Session and chained-agent semantics

The integrated ref must preserve session continuity through an agent loop:

1. model emits a tool call;
2. controlled executor runs it;
3. exact execution result is returned to the model/session;
4. the model continues from the same logical conversation state;
5. a subsequent tool call or final answer is associated with the correct request, model, session, and tested SHA.

The previously proven live required-session witness at `81ff2f2c...` is a regression baseline, not sufficient evidence for the new integration ref by itself.

### F5. OpenAI API policy fidelity

The integration must preserve tool policy across internal request conversion and both supported OpenAI-facing APIs used by the work:

- Chat Completions;
- Responses API;
- `tool_choice` including `auto`, `required`, and named tool;
- `parallel_tool_calls` policy where the API exposes it;
- no silent policy reset during request conversion or serialization.

Upstream may continue to change Responses API behavior. Before Maintainer PR extraction, rebase/replay analysis against then-current upstream is mandatory.

### F6. Live acceptance and evidence

The local acceptance harness must bind evidence to one exact candidate SHA and capture at minimum:

- source commit SHA;
- build identity and command;
- model identifier and model path/config identity without copying model binaries into evidence;
- OVMS endpoint and relevant serving configuration;
- request bodies;
- response bodies or normalized raw response artifacts;
- session identifier when used;
- seed and temperature where supported;
- controlled executor inputs/results for chained tests;
- per-case verdict;
- final summary verdict.

Fixtures and grounding data must be clearly separated from runtime provenance.

## Acceptance gates

The candidate is `LOCAL_ACCEPTED` only when all required gates pass on one exact candidate SHA:

| Gate | Required proof |
| --- | --- |
| G1 Build | Windows OVMS build succeeds for the exact candidate SHA. |
| G2 Parser | Native syntax, recursion, strings/paths, lossless numbers, malformed fail-closed behavior, unknown-tool rejection. |
| G3 Generation policy | `none`, `auto`, `required`, and named-tool behavior. |
| G4 Streaming | Split tags/arguments, incomplete calls, multi-call streaming progression. |
| G5 Agent loop | Tool call -> controlled execution -> tool result -> continuation -> next tool/final result. |
| G6 API policy | Chat Completions and Responses preserve applicable tool-selection and parallel-call policy. |
| G7 Live model | Real Gemma4 endpoint passes the bounded live acceptance matrix. |

The following equivalences are explicitly forbidden:

```text
UNIT_GREEN != LOCAL_ACCEPTED
BUILD_GREEN != LOCAL_ACCEPTED
ONE_SUCCESSFUL_TOOL_CALL != LOCAL_ACCEPTED

LOCAL_ACCEPTED =
  build
  + parser
  + required
  + named
  + auto
  + streaming
  + chained session
  + Responses policy
  + live Gemma4
```

If platform limitations prevent exact lazy-auto behavior, the candidate must not fabricate PASS. The corresponding case is classified as `BLOCKED_BY_PLATFORM` with raw evidence. Any required acceptance case classified `BLOCKED_BY_PLATFORM` makes the candidate `NOT_LOCAL_ACCEPTED` and prevents promotion to `MAINTAINER_PR_SOURCE` unless this design contract is explicitly revised in a later approved design change.

## Required acceptance matrix

The implementation plan must instantiate at least these behavior classes:

- AUTO prose path;
- AUTO tool path;
- AUTO schema pressure / invalid-tool attempt;
- REQUIRED valid tool call;
- REQUIRED impossible/invalid setup fail-closed;
- NAMED correct tool;
- NAMED attempt to call a different tool;
- STREAM AUTO with split tool syntax;
- STREAM nested arguments split across chunks;
- MULTI-CALL progression;
- CHAINED assistant tool call -> tool response -> continuation;
- Responses API policy-preservation cases;
- invalid structured-output configuration / grammar construction failure.

Tests must distinguish parser correctness from model behavior. A model choosing prose in a legal `auto` case is not a parser failure. A malformed executable tool call is.

## Implementation-session behavior

The implementation session will:

1. Re-resolve upstream main, integration spine, parser-hardening source, and any exact live-evidence baselines.
2. Create or verify `integration/gemma4-local-acceptance-2026.4` from the exact integration-spine SHA.
3. Inventory the parser-hardening commits after the common base and replay them one at a time in original order.
4. After every replay, run focused parser/generation tests relevant to that commit.
5. Resolve conflicts by preserving explicit feature contracts and adding/using regression tests, never merely by making the tree compile.
6. Verify that older `fix/gemma4-opencode-auto-tool-native` behavior is either already represented by the newer lazy-auto implementation or recorded as a missing contract. Do not merge the old branch wholesale.
7. Add or normalize a unified local-acceptance harness that emits exact-SHA evidence and a machine-readable summary.
8. Run offline/unit acceptance available in the implementation environment.
9. Produce one exact candidate SHA for checkout on the local Windows/Arc machine.
10. Run the live acceptance matrix on that exact SHA.
11. Preserve the local evidence bundle in a dedicated artifact/report path and commit only appropriate textual/small evidence artifacts.
12. Promote the SHA to `MAINTAINER_PR_SOURCE` only on explicit full acceptance.

## Non-goals and protected refs

This integration session does not:

- move fork `main`;
- modify upstream refs;
- merge any Maintainer PR;
- squash all historical Gemma4 experiments into one branch;
- claim upstream OVMS is generally inferior;
- claim streaming PASS from non-streaming evidence;
- claim lazy-auto is fully solved without live verification;
- rewrite old evidence to make it appear generated by the new candidate.

## Maintainer PR extraction after local acceptance

After one exact `LOCAL_ACCEPTED` ref exists, upstream work should be extracted as minimal reviewable patch series rather than submitting the integration branch wholesale. The expected decomposition is:

1. Gemma4 parser correctness and hardening.
2. Gemma4 guided-generation semantics (`required`, named, lazy-capable `auto`).
3. Streaming/session correctness where separable.
4. OpenAI Responses/tool-policy fidelity where still absent upstream.

Each patch series must be re-evaluated against the then-current upstream `main`, because upstream is actively changing Responses API and related serving behavior.

## Success criterion

The design succeeds when the project can point to one exact candidate SHA and one evidence bundle showing that the same code built and passed the complete required local Gemma4 acceptance matrix. Only that state authorizes Maintainer PR extraction.
