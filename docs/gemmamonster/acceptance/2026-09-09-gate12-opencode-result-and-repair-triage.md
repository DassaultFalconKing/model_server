# Gate12 OpenCode result and parser repair triage

**Date:** 2026-09-09  
**Execution branch:** `test/gemmamonster-gate12-20260909-e398363c`  
**Repair branch:** `repair/gemmamonster-gate12-parser-regressions-20260909`  
**Base SHA:** `e398363c2fe6f572a0fdc3ed9fd37c551fd73c76`  
**OpenCode start SHA:** `c4c5788f3207f36cadc122a291bcd689c2b3777e`  
**Remote execution SHA:** `6c5ee69d7c50486189734751016406c44b040311`  
**Local harness tip reported by OpenCode:** `950aa12cffed027fdcb43d715ac136d855e1d178`  
**Candidate source SHA:** `01ea946a5`  
**Candidate dir:** `C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z`  
**Binary SHA256:** `b26120393ceeba469858fb0380409cd715c04dcee58a186420448750cc7164d8`

This document records the OpenCode Gate12 handoff and starts the parser repair workstream. It is not an acceptance record. The reported verdict is **DO NOT PROMOTE**.

## 1. Remote verification boundary

The remote execution branch advanced from `c4c5788f3207f36cadc122a291bcd689c2b3777e` to `6c5ee69d7c50486189734751016406c44b040311` with five pushed commits. The local-only harness tip `950aa12cffed027fdcb43d715ac136d855e1d178` is intentionally excluded from remote and must not be used as the repair base.

Remote changed files versus `c4c5788f3207f36cadc122a291bcd689c2b3777e`:

- `scripts/gemmamonster/build-candidate.ps1`
- `scripts/gemmamonster/promote-candidate.ps1`
- `scripts/gemma4/collect-runtime-provenance.ps1`
- `src/test/llm/gemma4_fast/gemma4_recovery_contract_test.cpp`

The local-only `ab-evidence/live_chain_harness.py` is not part of this repair branch.

## 2. Build and Gate1 result reported by OpenCode

Reported build result:

- **BUILD:** PASS, exit 0
- static audit: 55 PASS / 1 WARN / 0 FAIL
- warning: dirty was sanctioned through `-AllowDirty`
- Bazel: 980 actions, about 639 seconds
- candidate manifest: `C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\manifest.json`

Reported Gate1 Jinja result:

- **GATE1_JINJA:** PASS
- command: `bazel test //src/test/llm/gemma4_overlay:gemma4_google_jinja_contract_test //src/test/llm/gemma4_overlay:gemma4_chat_template_overlay_contract_test`
- exit: 0
- test counts: overlay 7/7, Google Jinja contract 2/2
- environment correction required: `--test_env=PATH --test_env=GEMMA4_TOKENIZER_PATH`

The environment correction is accepted as a test environment issue, not a product regression.

## 3. Gate2 and full protocol result

Reported Gate2 streamer matrix result:

- **GATE2_STREAMER_MATRIX:** FAIL
- command actually used: `bazel test //src:ovms_test --test_filter=Gemma4ContentOwnsRouting*:Gemma4OutputParserTest.Streaming*:Gemma4V2ContractTest.Recovers*`
- exit: 3
- result: 11 ran / 5 passed / 6 failed
- note: `//src:llm_output_parser_tests` is a `cc_library`, not a runnable Bazel target; `//src:ovms_test` is the effective runner.

Reported full protocol runner result:

- **FULL_PROTOCOL_RUNNER:** FAIL, exit 1
- 5/6 protocol targets passed
- `gemma4_parser_contract_test`: 28/31, 3 failures
- manifest status: `built_not_accepted`
- protocol status: FAIL

## 4. Known parser failures requiring repair

### 4.1 Protocol failures

All three protocol failures have `toolCalls.size() == 0` instead of `1`.

1. `Gemma4ParserFastContractTest.AcceptsColonNameVariantWhenAnchored`
   - input shape: `<|tool_call>:question{...}` without `call:`
   - conflict: current literal-marker protection after `e53cc32d5b5f3db25ee311d3591416285a0f6a4f` requires canonical `call:` suffix after `<|tool_call>`.

2. `Gemma4ParserFastContractTest.PreservesNumbersBeyondMachinePrecision`
   - symptom: large-number call is dropped entirely.
   - likely repair area: numeric lexical preservation and malformed-number rejection must stay separated. Valid huge numbers must survive; malformed forms such as `1.`, `1e`, `-`, and `01` must still be rejected.

3. `Gemma4BareRecoveryContractTest.BareCallRecoverySurvivesToolNameChunkSplit`
   - input shape: `call:quest` + `ion{...}`.
   - conflict: bare-call split holding or viable-prefix recovery still fails for tool-name chunk split.

### 4.2 Gate2 streamer failures

1. `Gemma4OutputParserTest.StreamingWithBiggerChunks`
2. `Gemma4OutputParserTest.StreamingWithWhitespacesBetweenToolCalls`
3. `Gemma4OutputParserTest.StreamingWithToolCallWithEmptyParams`
4. `Gemma4OutputParserTest.StreamingWithToolResponseTokenAtTheEndOfGeneration`
5. `Gemma4OutputParserTest.StreamingWithMissingEndTagBeforeStop`
6. `Gemma4ContentOwnsRoutingContractTest.ContentThenToolCallStartHandoff`

The reported core handoff failure is `ContentThenToolCallStartHandoff`, where `done.has_value() == false`. This keeps Gate2 red and blocks promotion.

## 5. Wrapper-chain fixes already pushed

OpenCode reported and pushed minimal fixes for the candidate discipline scripts:

- `$Args` parameter binding in `build-candidate.ps1`
- array splat instead of hash splat
- `$Label:` delimiter in `promote-candidate.ps1`
- `$LASTEXITCODE` leakage from the version probe
- one missing include in `gemma4_recovery_contract_test.cpp`

These are accepted as infra/harness repairs, not parser acceptance.

## 6. Live/runtime status

Live status is **NOT accepted**.

Reported launch attempts:

- PID 2072: immediate loader death because the vault contained only `ovms.exe` without colocated runtime DLLs.
- PID 36012: started with expanded DLL path, Python 3.12.10 initialized, then exited before `/v1/models`; healthcheck failed after 8-minute polling window.
- Observed host condition: GPU LiveKernelEvents in the window.

One direct `ovms.exe --version` diagnostic run was disclosed after a `0xC0000135` loader failure. Subsequent runs used the launcher.

## 7. Repair constraints

Do not promote this candidate.

Do not use `950aa12cffed027fdcb43d715ac136d855e1d178` as a shared base. It is local-only and contains harness material intentionally kept out of origin.

The parser repair must preserve existing hardening seams:

- literal `<|tool_call>` content must not be truncated as a false tool opener;
- canonical `<|tool_call>call:name{...}` remains the primary anchored protocol;
- any support for `<|tool_call>:name{...}` must be explicitly treated as a legacy anchored compatibility variant, not generalized to arbitrary literal markers;
- bare `call:` recovery must remain line-start / indentation-bounded;
- unknown bare calls rewind and re-emit as content;
- anchored malformed or unknown calls remain fail-closed;
- valid large numeric lexemes must be preserved;
- malformed numeric lexemes must still be rejected;
- parser must emit at most one `Delta` per `parseChunk()` call and must not spin on STOP.

## 8. Initial repair hypotheses

These are hypotheses for the repair workstream, not approved fixes.

1. Anchored legacy colon variant:
   - Accept `<|tool_call>:name{...}` only when the `<|tool_call>` anchor is present and the post-anchor suffix is exactly `:` followed by a sane tool name and an argument opener.
   - Do not allow this variant for bare content.

2. Large numeric preservation:
   - Re-check the interaction between `normalizeJsonLosslessly`, `NumberPreservingWriter::RawNumber`, and the native value parser.
   - The desired split is: valid huge numbers pass lexically unchanged; invalid number-looking tokens fail closed.

3. Tool-name split recovery:
   - Re-check `findRecoverableBareCall` and tail holdback interaction for `call:quest` followed by `ion{...}`.
   - The prefix must be held if it can still grow into one allowed tool name.

4. Content-owned handoff:
   - Reproduce `ContentThenToolCallStartHandoff` first.
   - Verify whether the false negative comes from `findAnchoredToolCallStart`, `parseInContentState`, outer `OutputParser::parseToolCallChunk`, or STOP/finish handling.

## 9. Required verification before any promotion

At minimum, repair must rerun:

```bat
bazel test //src:ovms_test --test_filter=Gemma4ContentOwnsRouting*:Gemma4OutputParserTest.Streaming*:Gemma4V2ContractTest.Recovers*
```

Then rerun:

```bat
.\scripts\gemmamonster\build-candidate.ps1 -RepoRoot . -Label gate12-repair -RunProtocol
```

Promotion remains blocked until Gate2 and the full protocol runner pass or until remaining failures are reclassified with evidence outside Gemma4 parser scope.
