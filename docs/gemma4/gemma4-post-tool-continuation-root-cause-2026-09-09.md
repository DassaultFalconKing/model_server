# Gemma4 post-tool continuation root cause (2026-09-09)

Root-cause + implementation session for Gemma4 post-tool continuation on OVMS 2026.5.
No speculative fixes without reproducible causal evidence.

## Identity

```text
BASE_SHA: 2d17e36f39412f18df558c49c6bc4661b833f675
  Subject: feat(gemma4): complete 2026.5 forward-port acceptance
  Date: 2026-09-09 05:07:21 +0200

INVESTIGATION_NOTE_SHA: 767aa3a3e1998c968bc7d5c7487a5e09b449a4ac
  Subject: docs(gemma4): record OpenCode first-tool-call stop root cause
  Date: 2026-09-09 05:37:43 +0200
  Path: docs/gemma4/opencode-first-toolcall-stop-2026-09-09.md
  Note: origin/integration/ovms-2026.5-forward-port == 767aa3a3 at fetch time.
  The forward-port base required by this session remains 2d17e36f, not 767aa3a3.

REFIT_ORIG_SHA (origin/fix/gemma4-reasoning-semantic-refit at fetch):
  5038a8322762e25af65b553913af22afbe5c27c6
  Subject: test(gemma4): cover post-tool reasoning boundary splits
  Date: 2026-09-09 05:37:10 +0200

TESTED_SHA (this session, after minimal compile/semantic fixes):
  7f5fa2b9ae840f095aee8192cc7b4e41bae5bf7f
  Branch: session/gemma4-post-tool-2026-09-09
  Parent: 5038a8322762e25af65b553913af22afbe5c27c6
  Worktree: C:\git\gemma4-posttool-2026-09-09 (detached at 5038a83, then branched)
  Main repo for ref resolution: C:\git\g4-final-review (fetched 2026-09-09)

BRANCH: session/gemma4-post-tool-2026-09-09 (based on 5038a83, which is based on 2d17e36f)
BASE_SHA: 2d17e36f39412f18df558c49c6bc4661b833f675
TESTED_SHA: 7f5fa2b9ae840f095aee8192cc7b4e41bae5bf7f

MERGE_BASE (refit vs base):
  git merge-base 5038a83 2d17e36 == 2d17e36f39412f18df558c49c6bc4661b833f675
  Verdict: refit remains based on exact forward-port SHA as required.

MAIN (untouched):
  local main: 73419fca131afc7389e493cf3f2bbb7ef7ac8ec6
  origin/main: 3a1c53a0004a0a59d57a74b70b9db17bb0159ab9
  No move performed in this session.

INTEGRATION (untouched, no merge):
  integration/ovms-2026.5-forward-port: 767aa3a3e1998c968bc7d5c7487a5e09b449a4ac
  origin/integration/ovms-2026.5-forward-port: 767aa3a3e1998c968bc7d5c7487a5e09b449a4ac
  No merge into integration performed.
```

## Correction to investigation note 767aa3a3

The note states:

> `auto` still has no triggered structured tags

This is false as written for 767aa3a3.

`Gemma4GenerationConfigBuilder::parseConfigFromRequest` does build `TriggeredTags`
for `tool_choice=auto` (see `src/llm/io_processing/generation_config_builder.hpp`,
`buildAutoToolGrammar`, `setStructuralTagsConfig`).

Proven in this session by
`Gemma4GenerationContractTest.AutoUsesTriggeredToolGrammarAndHardChoicesStayImmediateAndRepeatable`
(PASS, 14/14 generation-contract tests with correct tokenizer path).

What was NOT proven by source alone is whether the grammar survives runtime
validation. That is tested below. The correct failure hypothesis is:

```text
auto grammar constructed
-> validation fails
-> generic fallback calls unsetStructuredOutputConfig()
-> request proceeds unguided
```

Hard choices are fail-closed (`shouldPreserveStructuredOutputOnValidationFailure()==true);
`auto` is not (may fallback). See `src/llm/apis/openai_api_handler.cpp:379-384`.

## Phase 1: build

Worktree: `C:\git\gemma4-posttool-2026-09-09`, branch
`session/gemma4-post-tool-2026-09-09`.

### Initial build at exact 5038a83 (before session fixes)

Command (PowerShell, workdir = worktree):

```powershell
$env:PATH = "C:\opt;C:\opt\Python312;C:\opt\Python312\Scripts;C:\opt\msys64\usr\bin;C:\opt\curl-8.21.0_7-win64-mingw\bin;" + $env:PATH
$env:BAZEL_SH = "C:\opt\msys64\usr\bin\bash.exe"
$env:BAZEL_VS = "C:\BuildTools"
$env:BAZEL_VC = "C:\BuildTools\VC"
$env:BAZEL_VC_FULL_VERSION = "14.44.35207"
C:\opt\bazel.exe --output_user_root=C:\opt build `
  --config=win_mp_on_py_off `
  --disk_cache=C:\opt\bazel-disk-cache\win_mp_on_py_off `
  --repository_cache=C:\opt\bazel-repository-cache `
  --action_env OpenVINO_DIR=C:/opt/openvino/runtime/cmake `
  --action_env OpenCV_DIR=C:/opt/opencv_4.14.0 `
  --jobs=8 --verbose_failures `
  //src/test/llm/gemma4_fast:gemma4_parser_contract_test
```

Result: FAIL (compile).

```text
src/test/llm/gemma4_fast/gemma4_reasoning_semantic_refit_test.cpp(96):
  error C2248: 'ovms::OutputParser::setImplicitReasoningStart':
  cannot access private member declared in class 'ovms::OutputParser'
src/test/llm/gemma4_fast/gemma4_reasoning_semantic_refit_test.cpp(103): same
src/test/llm/gemma4_fast/gemma4_reasoning_semantic_refit_test.cpp(119): same
```

`BUILD` target in this revision builds both contract and refit tests from one
`cc_test(name="gemma4_parser_contract_test")` with srcs:

```text
gemma4_parser_contract_test.cpp
gemma4_reasoning_semantic_refit_test.cpp
```

There is no separate semantic-refit `cc_test` target; running
`//src/test/llm/gemma4_fast:gemma4_parser_contract_test` runs both suites.

### Session fix 1 (compile/test integration only)

`src/test/llm/gemma4_fast/gemma4_reasoning_semantic_refit_test.cpp` called
private `OutputParser::setImplicitReasoningStart(true)`.

Public API used by production (`src/llm/servable.cpp`) and by
qwen3/minicpm5 tests is:

```cpp
detectAndSetImplicitReasoningStart(renderedPromptEndingWithStartTag)
```

Changed 3 call sites to:

```cpp
parser.detectAndSetImplicitReasoningStart("prompt<|channel>thought\n");
```

No parser semantics changed in this step.

Rebuild: SUCCESS (86s, 52 actions).

Direct run (see TESTS) then showed 20/22 PASS, 2/22 FAIL, both in
implicit-reasoning refit tests. That failure is the evidence that permitted a
semantic fix (see below). It proved the test now exercises the real public
detection path, which was broken for Gemma4.

### Session fix 2 (test-proven semantic defect)

`OutputParser::detectAndSetImplicitReasoningStart` did:

```cpp
std::string trimmed = renderedPrompt;
rtrim(trimmed);
endsWith(trimmed, tag) // tag = "<|channel>thought\n"
```

`rtrim` removes trailing `\n`, so `trimmed` can never end with a tag that
itself ends with whitespace. For Gemma4 this detection was logically
impossible: no prompt ending with `<|channel>thought\n` could ever activate
implicit reasoning.

Other parsers (qwen3 `<think>`, minicpm5 `<think>`, lfm2 `<think>`) use tags
without trailing whitespace, so they were unaffected. This explains why the
bug was Gemma4-specific and why the refit test bypassed it via the private
setter.

Fix in `src/llm/io_processing/output_parser.cpp`:

```cpp
// Tags may end with whitespace (e.g. Gemma4 "<|channel>thought\n").
// Since the prompt is rtrimmed, compare against an rtrimmed tag copy.
bool detected = std::any_of(... [&](const std::string& tag) {
    if (tag.empty()) return false;
    std::string trimmedTag = tag;
    rtrim(trimmedTag);
    return !trimmedTag.empty() && endsWith(trimmed, trimmedTag);
});
```

Generic, preserves qwen/minicpm behavior (their trimmed tags are identical to
originals), fixes Gemma4. No model-specific branching added to `OutputParser`
beyond the existing config-driven design.

Rebuild after fix 2: SUCCESS (18s incremental, 4 actions).

```text
Target //src/test/llm/gemma4_fast:gemma4_parser_contract_test up-to-date:
  bazel-bin/src/test/llm/gemma4_fast/gemma4_parser_contract_test.exe
```

Binary SHA256 (post-fix):

```text
gemma4_parser_contract_test.exe:
  8E39491BF20AB6DA73C245276907239A70E59B1DD16D2807034D9B55584FF2EF
gemma4_generation_contract_test.exe:
  B1A7648097FCF80F253E67D2390AF149BBECD6BCDA42358ECDF511C96E7535A1
Source HEAD for both binaries:
  7f5fa2b9ae840f095aee8192cc7b4e41bae5bf7f
```

Note: first `bazel` invocation in this session failed with
`msvc_not_found` because `BAZEL_VS` was set to the Jenkins path
`C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`, which does
not exist on this host. Correct host path is `C:\BuildTools`
(`VCToolsVersion 14.44.35207`). All successful builds above use the corrected
env. This is environment setup, not a source change.

## TESTS

### Parser (contract + refit, one target)

Command:

```powershell
$env:GEMMA4_TOKENIZER_PATH="C:\git\model_server-gemma4-fast\src\test\llm_testing\OpenVINO\gemma-4-E4B-it-int4-ov"
& "C:\git\gemma4-posttool-2026-09-09\bazel-bin\src\test\llm\gemma4_fast\gemma4_parser_contract_test.exe"
```

Worktree `src/test/llm_testing/OpenVINO/gemma-4-E4B-it-int4-ov` does not exist
in the fresh worktree (model files are git-ignored/downloaded). `GEMMA4_TOKENIZER_PATH`
points at the existing copy in `model_server-gemma4-fast` (same bytes).

Result at TESTED_SHA 7f5fa2b9:

```text
[==========] Running 22 tests from 2 test suites.
[----------] 18 tests from Gemma4ParserFastContractTest -- all OK
[----------] 4 tests from Gemma4ReasoningSemanticRefitTest -- all OK
[==========] 22 tests ran.
[  PASSED  ] 22 tests.
exit code: 0
```

Breakdown:

```text
Gemma4ParserFastContractTest: 18/18 PASS
  (includes AcceptsDirectCallAfterReasoning, ReasoningBoundaryChunkKeepsText,
   CompleteCallSurvivesEveryByteSplit, NonGemmaReasoningDoesNotTreatLiteralToolMarkerAsBoundary,
   PreservesNumbersBeyondMachinePrecision, ManyCallsReleaseConsumedBufferAndKeepOwnedDeltas)
Gemma4ReasoningSemanticRefitTest: 4/4 PASS
  ToolStartImplicitlyEndsOpenReasoning: PASS
  ImplicitPromptReasoningCanTransitionDirectlyToTool: PASS
  SameChunkReasoningPrefixIsPreservedBeforeToolHandoff: PASS (failed before fix 2)
  PartialToolMarkerIsHeldBackInsteadOfLeakingIntoReasoning: PASS (failed before fix 2)
```

Intermediate result after fix 1 only (before fix 2), same command:

```text
[  PASSED  ] 20 tests.
[  FAILED  ] 2 tests:
  SameChunkReasoningPrefixIsPreservedBeforeToolHandoff
    holds_alternative<ReasoningDelta>(*reasoning) == false
  PartialToolMarkerIsHeldBackInsteadOfLeakingIntoReasoning
    holds_alternative<ReasoningDelta>(*reasoning) == false
exit code: 1
```

This is the single-variable evidence for the implicit-detection defect:
same binary, same prompt (`prompt<|channel>thought\n`), same chunks; only
`detectAndSetImplicitReasoningStart` logic differs before/after fix 2.
Before: implicit never activates, `Need another tool` prefix is emitted as
content (or dropped), not `ReasoningDelta`. After: `ReasoningDelta("Need another tool")`.

`bazel test //src/test/llm/gemma4_fast:gemma4_parser_contract_test` was not
used as the pass/fail gate because `bazel test` execution in this Windows env
fails with missing-DLL exit `-1073741515` even for previously-passing binaries
(see `model_server-gemma4-fast/bazel-testlogs/.../test.log` at 2026-09-09
04:42). Direct exe execution with `GEMMA4_TOKENIZER_PATH` set is the reliable
gate and exercises the same binary. Build itself was via `bazel build` above.

BUILD:

```text
BUILD: //src/test/llm/gemma4_fast:gemma4_parser_contract_test (single cc_test, both suites)
Build command exit: 0 (post-fix)
Binary SHA256: 8E39491B...FF2EF (see above)
Source HEAD: 7f5fa2b9ae840f095aee8192cc7b4e41bae5bf7f
```

### Generation config (auto guidance)

Command (build):

```powershell
C:\opt\bazel.exe --output_user_root=C:\opt build --config=win_mp_on_py_off ... //src/test/llm/generation_config:gemma4_generation_contract_test
```

Build exit: 0 (177s, 832 actions).

Direct run initially (cwd=C:\git, wrong tokenizer resolution) gave 12/14 PASS,
2 FAIL with:

```text
ov::AssertFailure: Check '!vocab_vector.empty()' failed at xgrammar_backend.cpp:19:
Structured output requires the tokenizer to expose its full vocabulary...
```

Root cause of those 2 failures was the test helper
`getGenericFullPathForSrcTest("/ovms/src/test/llm_testing/...")` resolving to
`C:/git/src/test/...` when cwd is `C:\git` (no `bazel-out` in path), not a
grammar defect. After copying the real tokenizer to the resolved path
(`C:\git\src\test\llm_testing\OpenVINO\gemma-4-E4B-it-int4-ov`, byte-identical
to the fast-repo copy), rerun:

```text
[==========] 14 tests ran.
[  PASSED  ] 14 tests.
exit code: 0
```

Relevant cases:

```text
AutoUsesTriggeredToolGrammarAndHardChoicesStayImmediateAndRepeatable: PASS
  - auto builds TriggeredTags{triggers={"<|tool_call>"}, at_least_one=false}
  - proves "auto has no triggered tags" is false
AutoTriggeredGrammarValidatesWithGemmaTokenizer: PASS (274ms with real tokenizer)
  - proves TriggeredTags validate() does NOT throw for empty-schema tools
  - therefore generic fallback unsetStructuredOutputConfig() is NOT taken
    for this schema; generation begins guided
HardChoicesAllowReasoningBeforeMandatoryToolSelection: PASS
OpenCodeQuestionSchemaIsEnforcedForAutoAndRequired: PASS (construction only)
```

Not proven: `validate()` with the full OpenCode `question` schema
(`openCodeQuestionSchema` in the test) plus the real Gemma4 tokenizer.
Construction for that schema is proven; validation for that exact schema was
not executed in this session. See verdicts.

## LIVE_OVMS

```text
LIVE_OVMS: NOT_RUN
```

No live OVMS server was started from TESTED_SHA in this session. No
request1/tool-result/request2 continuation matrix (cases A-F) was executed
live. No raw token IDs / raw decoded special-token stream / generation config
/ structured-output validation logs were captured from a live process.

Reason: live matrix requires GPU model load
(`gemma4-26-heretic`, Profile E, overlay
`C:\llm\models\OpenVINO\gemma4-google-template-overlay`), fixed seeds, and
multiple controlled restarts. This session prioritized the blocking compile
defect and the test-proven parser defect, which had to pass before any live
conclusions are meaningful.

Prior live observation (from 767aa3a3 note, not reproduced here):

```text
request2 -> finish_reason=stop, 4 completion tokens, empty content, no tool calls, HTTP 200
same request2 shape with temperature:0 -> following tool call
```

Without the four-boundary capture (OpenAI JSON / rendered prompt / RAW model
output with special tokens / parser deltas), that observation cannot
distinguish:

```text
RAW MODEL DID NOT GENERATE TOOL CALL
vs
RAW MODEL GENERATED TOOL CALL BUT PARSER LOST IT
```

Therefore no live generation/scheduler claim is marked confirmed in this report.

## OPENCODE

```text
OPENCODE: NOT_RUN
```

No real OpenCode loop (`tool #1 -> result -> tool #2 -> result -> answer`) was
executed against TESTED_SHA in this session.

## Causal table

| Hypothesis | Evidence | Verdict |
|---|---|---|
| Jinja overlay broken | Request2 rendered and generated (HTTP 200, no `'str' object has no attribute 'get'`, no 400). Same request2 payload with `temperature:0` produced a following tool call (767aa3a3 note). If missing `<|turn>model` suffix forced EOS, temperature could not recover it. Overlay tail after `tool_response` with thinking off intentionally leaves turn open (Google same-turn continuation). | rejected |
| sampling EOS (unspecified temperature/seed → 4-token empty stop) | Prior observation: no `temperature`/`seed` in OpenCode request, OVMS `Randomizing rng_seed`, 4-token empty `stop`; temp 0 recovered continuation. But mitigation in 767aa3a3 changed title + temperature + thinking + small_model simultaneously. No single-variable live control (same payload/seed, temp default vs 0, all else held constant) was run in this session. Code path confirmed (`BaseGenerationConfigBuilder`: model temp kept, `do_sample = temp>0`, random `rng_seed` when unset), but causal link to this specific empty-stop not isolated. No global temp-0 change made. | NOT_PROVEN (strong candidate, not confirmed) |
| title contention (Profile E max_num_seqs:1 + prefix cache corrupted by concurrent title request) | Prior observation: title (`small=true`, same model/GPU) at 05:19:05 overlapped main at 05:19:07, `All requests:2; Scheduled:2` on single-seq profile with prefix cache. But mitigation disabled title AND changed temperature/thinking/model simultaneously. No single-variable run (same parser/temp/seed/payload, title off vs on) in this session. No scheduler/cache logs proving output corruption vs latency-only effect. | NOT_PROVEN (downgraded from “confirmed”; needs Phase 4 control) |
| auto grammar absent | `Gemma4GenerationConfigBuilder` builds `TriggeredTags` for `auto` (code + `AutoUsesTriggeredToolGrammar...` PASS). Statement in 767aa3a3 that auto has no triggered tags is false for 767aa3a3/5038a83/7f5fa2b9. | rejected |
| auto grammar validation fallback (constructed but removed before generation) | For empty-schema tools + real Gemma4 tokenizer, `validate()` succeeds (`AutoTriggeredGrammarValidatesWithGemmaTokenizer` PASS after correct tokenizer path). Hence fallback `unsetStructuredOutputConfig()` is not taken for that case; generation begins guided. For the full OpenCode `question` schema, construction is proven but `validate()` with real tokenizer was not executed here. No xgrammar error captured for that schema. Do NOT fix by forcing `required`; auto must permit prose (`at_least_one=false` asserted in tests). | rejected for tested schemas; NOT_PROVEN for OpenCode complex schema |
| reasoning→tool parser transition (thought directly into `<\|tool_call>` without `<channel\|>`) | Old `OutputParser` in REASONING only looked for reasoning end marker; Gemma4 legally emits `<|channel>thought ... <\|tool_call>call:foo{...}<tool_call\|>` (vLLM supports REASONING+TOOL_START → implicit end). Refit adds `toolStartTerminatesReasoning` + holdback for split `<\|tool_` markers. Proven by 4/4 refit tests PASS at 7f5fa2b9 (2/4 failed before implicit-detection fix, proving tests exercise the path). Old code would misclassify/lose this boundary. Whether the observed OpenCode 4-token empty-stop contained a raw `<\|tool_call>` is unknown (no raw capture), so role in that incident is not proven. Defect itself is confirmed; incident causality is not. | supported as real defect, fixed; incident causality NOT_PROVEN |
| implicit-reasoning detection (prompt ends inside `<\|channel>thought`) | Proven impossible before fix: `rtrim(prompt)` vs untrimmed tag `<\|channel>thought\n` can never match. Falsifier: same test binary, same prompt `prompt<|channel>thought\n`, same chunks — before fix 2/4 refit tests FAIL with content instead of `ReasoningDelta`; after fix 4/4 PASS. Single variable was the `rtrim(tag)` comparison. Production path `servable.cpp:detectAndSetImplicitReasoningStart(req.promptText)` affected whenever template suffix is `<\|channel>thought\n` (thinking on after tool response). | supported (confirmed defect, fixed) |
| session dependency | `OVMS_SESSION_STORE_DIR` unset, OpenCode sends no `X-OVMS-Session-ID` (767aa3a3). No session journal involved in observed stall. Stateless continuation (new HTTP request with `[user, assistant(tool_calls), tool(result)]`, no session header) not yet run live here. | rejected as cause of observed stall; live stateless acceptance NOT_RUN |
| scheduler/concurrency/prefix-cache interaction | No live matrix (title off vs on, all else fixed, fixed seed, multiple reps) and no scheduler/cache logs collected here. | NOT_PROVEN |

Single-variable falsifiers/controls:

```text
Jinja: same request2 + temperature:0 -> tool call (prior observation, needs rerun
  with full four-boundary capture to be airtight).

Sampling: REQUIRED control (not run): same request1/tool-result/request2, same
  parser/refit, same seed, thinking flag fixed, title off, temp default vs 0,
  compare raw token streams. If raw is "<thought-ish> EOS" with no tool marker
  in default but tool marker with temp 0, generation causality supported.

Title: REQUIRED control (not run): hold parser/temp=0/seed/thinking/payload/
  model/profile constant; run N reps with no concurrent title vs concurrent
  title on same local model; compare raw streams + scheduler/cache logs.

Auto fallback: CONTROL (partially run): build auto grammar for OpenCode schema,
  call validate(tokenizer) with real Gemma4 tokenizer, record throw vs no-throw
  and whether unsetStructuredOutputConfig() clears it. Empty-schema case done
  (no throw). OpenCode-schema case still required.

Parser: DONE: refit tests + implicit-detection before/after (20/22 -> 22/22).
  Raw-vs-parser distinguisher for live: log raw token IDs + decoded
  special-token stream alongside API deltas; tool marker in raw but absent in
  API => parser; absent in raw => generation.

Session: CONTROL (not run): stateless HTTP (no X-OVMS-Session-ID) with
  [user, assistant(tool_calls), tool(result)] -> expect tool call or meaningful
  continuation; proves no session dependency.
```

## Phase 6 coverage (refit vs required streams)

```text
Normal thought then content
  "<|channel>thought\nabc<channel|>final answer"
  Covered indirectly (ReasoningBoundaryChunkKeepsText + content path).
  No dedicated refit test; no leakage observed in contract suite. NOT_PROVEN as
  dedicated case, no failure seen.

Thought directly into tool call
  "<|channel>thought\nabc<|tool_call>call:foo{...}<tool_call|>"
  Covered: ToolStartImplicitlyEndsOpenReasoning PASS.
  Expected reasoning=abc, tool_call=foo(...): PASS.

Implicit reasoning start after tool result
  Prompt ends with "<|channel>thought\n", output begins with reasoning text.
  Covered: ImplicitPromptReasoningCanTransitionDirectlyToTool PASS (after fix 2);
  SameChunk... PASS. Production detection fixed.

Split tool marker ("<|tool_" + "call>...")
  Covered: PartialToolMarkerIsHeldBackInsteadOfLeakingIntoReasoning PASS.
  Partial opener returns nullopt, no leak into reasoning; handoff preserves prefix.

Explicit duplicate reasoning opener (prompt implies reasoning, model re-emits opener)
  Not a dedicated test. Code handles: Gemma4ReasoningParser strips startTag
  exactly once at phase entry (phaseEntryTagConsumed); implicit path with no
  opener in text leaves text intact; duplicate opener is stripped, not leaked.
  Logic reviewed, live/streaming coverage NOT_RUN.
```

vLLM comparison: refit ports the state-machine semantics
(REASONING + TOOL_START → implicit REASONING_END → TOOL_CALL_START + partial
opener holdback), not Python/Rust structure, into `OutputParser` +
`OutputParsingConfig::toolStartTerminatesReasoning` + `Gemma4ReasoningParser`.
Matches the semantic requirement stated in the session brief.

## Acceptance (per brief)

```text
1. Gemma4 parser unit tests: PASS (18/18)
2. New reasoning semantic-refit tests: PASS (4/4, total 22/22)
3. Existing Gemma4 tool parser tests: PASS (included in 18/18 contract suite)
4. tool_choice=auto guided-generation path verified: PARTIAL
   - construction + empty-schema validation: PASS (14/14 generation-contract)
   - OpenCode complex-schema validation: NOT_PROVEN
5. Stateless OpenAI-compatible continuation (no session header): NOT_RUN
6. Real OpenCode loop (tool1->result->tool2->result->answer): NOT_RUN
7. Thinking enabled run: NOT_RUN (live)
8. Thinking disabled run: NOT_RUN (live)
9. No parser marker leakage (unit): PASS (split-marker holdback test + contract suite)
10. No empty stop accepted as success: PASS (this report marks live empty-stop as unresolved)
```

## Verdicts (exact tokens only)

```text
PARSER_REFIT: PASS
AUTO_GUIDANCE: NOT_PROVEN
GENERATION_POLICY: NOT_PROVEN
TITLE_CONCURRENCY: NOT_PROVEN
STATELESS_TOOL_LOOP: NOT_RUN
OPENCODE_TOOL_LOOP: NOT_RUN
OVERALL: FAIL
```

`OVERALL: FAIL` because live stateless/OpenCode continuation, thinking on/off
live runs, and single-variable generation/title controls were not executed.
Do not call the bug fixed. Parser unit work is PASS; system-level
post-tool continuation is not proven.

## Changes in this session (vs 5038a83)

```text
session/gemma4-post-tool-2026-09-09: 7f5fa2b9ae840f095aee8192cc7b4e41bae5bf7f
parent: 5038a8322762e25af65b553913af22afbe5c27c6
merge-base with 2d17e36f: 2d17e36f (unchanged, refit still based on base)

1. src/test/llm/gemma4_fast/gemma4_reasoning_semantic_refit_test.cpp
   - private setImplicitReasoningStart -> public detectAndSetImplicitReasoningStart
   - compile fix; exposes real detection path to tests

2. src/llm/io_processing/output_parser.cpp (detectAndSetImplicitReasoningStart)
   - compare rtrimmed prompt against rtrimmed tag
   - fixes impossible Gemma4 implicit detection; generic, no model branch

No generation-policy change (no global temperature=0).
No auto-semantics change (at_least_one=false preserved).
No main/integration move or merge.
```

## Next steps (to reach PASS)

```text
1. Four-boundary logging (request JSON / rendered prompt / raw IDs+special-token
   decode / parser deltas + generation config/tool_choice/temp/seed/do_sample/
   structured-output presence+validation+fallback) for post-tool request.
2. Matrix A-F (same payload, fixed seed): old/refit x temp default/0 x title
   off/on x thinking false/true. Record raw streams.
3. Title single-variable (temp 0, fixed seed, N reps, title off vs on) + scheduler/cache logs.
4. Auto validation with OpenCode question schema + real tokenizer; capture xgrammar error if any.
5. Stateless HTTP + OpenCode live loops, thinking on/off, marker-leakage check.
6. If sampling EOS confirmed narrowly (post-tool + auto + gemma4 only), implement
   Gemma4-specific action-selection policy with regression test; do not globally
   hardcode temperature.
```
