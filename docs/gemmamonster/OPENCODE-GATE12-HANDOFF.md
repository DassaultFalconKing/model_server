# OpenCode Gate 1/2 Candidate Handoff

**Branch to build from:** `test/gemmamonster-gate12-20260909-e398363c`  
**Required base lineage:** this branch is based on `e398363c2fe6f572a0fdc3ed9fd37c551fd73c76` plus candidate-discipline docs/scripts.  
**Do not build from:** `integration/gemma4-parser-generator-refit-next` directly for this run.  
**Do not build from:** `infra/gemmamonster-candidate-discipline-20260909` directly for this run.

This branch is the OpenCode execution lane. It contains both the Gate 1/2 Gemma4 parser/generator work and the candidate-discipline tooling needed to prevent anonymous binaries, lost logs, and post-hoc folklore.

## Before doing anything

Run:

```powershell
git fetch origin
git checkout test/gemmamonster-gate12-20260909-e398363c
git reset --hard origin/test/gemmamonster-gate12-20260909-e398363c
git rev-parse HEAD
git status --short
```

Expected:

- `git status --short` is empty;
- HEAD is on `test/gemmamonster-gate12-20260909-e398363c`;
- any source changes must be committed only to this branch.

## Read first

Read these files before modifying or running anything:

1. `docs/gemmamonster/CANDIDATE-DISCIPLINE.md`
2. `docs/gemmamonster/BRANCH-LEDGER.md`
3. `docs/gemmamonster/KNOWN-GOOD.md`
4. `docs/gemmamonster/2026-09-09-content-owned-boundaries-port-contract.md`
5. `docs/gemmamonster/2026-09-09-jinja-contract-verification.md`
6. `docs/superpowers/plans/2026-09-09-gemmamonster-candidate-discipline.md`

## Hard rule

Do not run `ovms.exe` directly.

Use candidate directories only:

```powershell
.\scripts\gemmamonster\build-candidate.ps1 -RepoRoot . -Label gate12-opencode -RunProtocol
```

The build wrapper must create a candidate directory under:

```text
C:\gemmamonster-artifacts\candidates\
```

The candidate directory must contain at least:

```text
manifest.json
sha256sums.txt
build.log
ovms.exe
```

If protocol tests run, it must also contain/copy protocol summary or logs referenced from `manifest.json`.

## Launch rule

Launch only through:

```powershell
.\scripts\gemmamonster\launch-candidate.ps1 `
  -CandidateDir C:\gemmamonster-artifacts\candidates\<candidate-dir> `
  -ModelPath <absolute-model-path> `
  -ModelName <model-name> `
  -RestPort 8000
```

The launcher must reject:

- missing `manifest.json`;
- binary SHA mismatch;
- missing `ovms.exe`;
- missing model path;
- port already occupied.

## Gate 1: Jinja contract

Run or confirm these tests:

```powershell
bazel test //src/test/llm/gemma4_overlay:gemma4_google_jinja_contract_test
bazel test //src/test/llm/gemma4_overlay:gemma4_chat_template_overlay_contract_test
```

Gate 1 is not PASS unless logs and exit codes are captured.

## Gate 2: streamer/content-owned boundary matrix

Run:

```powershell
bazel test //src:llm_output_parser_tests --test_filter=Gemma4ContentOwnsRouting*:Gemma4OutputParserTest.Streaming*:Gemma4V2ContractTest.Recovers*
```

Also run the broader parser binary when practical:

```powershell
bazel test //src:llm_output_parser_tests
```

Known unrelated failures must be explicitly named. Do not hide Gemma4 failures behind unrelated Devstral tokenizer failures. Do not call a mixed binary PASS if non-Gemma tests fail.

## Required regression surface

Confirm Gemma4 still preserves:

- `UNKNOWN -> CONTENT`;
- consecutive CONTENT chunks exactly once;
- CONTENT followed by `<|tool_call>`;
- split `call` + `:` under streamer delay;
- split `<|tool_call>`;
- unknown bare call rewinds to content;
- anchored unknown call remains fail-closed/drop;
- final STOP does not spin;
- literal `<|tool_call>` remains content unless followed by `call:`;
- viable-prefix bare-call recovery, including `call:quest` + `ion{...}`;
- rejection of impossible prose such as `call:question prose`;
- malformed numeric rejection: `1.`, `1e`, `-`, `01`;
- lexical preservation for valid large/high-precision numbers;
- unique IDs/indices for repeated same-function calls;
- reasoning-to-tool handoff with special-token boundary preservation.

## Promotion dry run

After a candidate is built and protocol logs exist, run:

```powershell
.\scripts\gemmamonster\promote-candidate.ps1 `
  -CandidateManifest C:\gemmamonster-artifacts\candidates\<candidate-dir>\manifest.json `
  -RepoRoot . `
  -DryRun
```

Do not update integration branches or tags from this test branch. Promotion is evidence generation only unless explicitly authorized later.

## Required final report

Return exactly this structure:

```text
BRANCH:
BASE_SHA:
START_HEAD_SHA:
FINAL_HEAD_SHA:
COMMITS:
FILES_CHANGED:
CANDIDATE_DIR:
MANIFEST:
BINARY_SHA256:
BUILD:
GATE1_JINJA:
GATE2_STREAMER_MATRIX:
FULL_PROTOCOL_RUNNER:
KNOWN_FAILURES:
PROMOTION_DRY_RUN:
ARTIFACTS:
RECOMMENDATION:
```

Allowed status values:

```text
PASS
FAIL
NOT_RUN
BLOCKED
```

No sentence may imply success unless it is backed by a command, log path, and exit code. This is not etiquette; this is how we stop losing binaries like civilization has learned nothing since `/tmp` was invented.
