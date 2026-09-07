# Execution session: Gemma4 local acceptance — build `integration/gemma4-local-acceptance-2026.4`, emit one TEST_SHA

> **Authority prompt.** A coding agent executing this plan works in `DassaultFalconKing/model_server`.
> Its task ends with a single exact `TEST_SHA` and the report block from §7. Nothing else counts as done.
>
> **Status boundary (read first).** The implementation session has NOT been executed yet.
> There is currently NO `integration/gemma4-local-acceptance-2026.4` ref, NO `TEST_SHA`,
> and NO build PASS anywhere. This document is the work program, not a green checkmark.
> If any gate cannot run in your environment, report `BLOCKED`/`NOT_RUN` with evidence —
> never `PASS` by intent.

## 1. Architecture (what you are building)

```text
generation/API spine
        +
5 parser-hardening commits
        |
        v
integration/gemma4-local-acceptance-2026.4
        |
        +--> parser tests
        +--> generation tests
        +--> OpenAI policy tests
        +--> acceptance/harness tests
        +--> Windows runner
        |
        v
      TEST_SHA  (exact 40-char HEAD after all gates below are green, live excluded)
```

Downstream (OUT OF SCOPE for this session, listed so you do not attempt it):

```text
TEST_SHA -> Windows Arc/Gemma4 machine: build exact TEST_SHA -> G1..G7 live acceptance
  +--> NOT_LOCAL_ACCEPTED -> fix -> new TEST_SHA (new session)
  `--> LOCAL_ACCEPTED -> MAINTAINER_PR_SOURCE: YES -> minimal upstream PR1..PR4
```

## 2. Refs — re-resolve, do not trust blindly

Run before anything else:

```powershell
git fetch origin --prune
git fetch upstream --prune
git rev-parse upstream/main
git rev-parse origin/main
git rev-parse origin/clean/gemma4-tools-minimal
```

Expected values (2026-09-07; if they differ, record actuals and continue only if §8 allows):

```text
UPSTREAM_MAIN:      5fe145e54064d7a048fd7cdc9603f4bde6f0f175
FORK_MAIN:          be410567f2b3f8146eda87087beb59b67199c893
CLEAN_PORT_TIP:     f919205576f9278d96071eed9e419da0c4fdc15f   (origin/clean/gemma4-tools-minimal, 18 commits)
```

Notes you must respect:

- `CLEAN_PORT_TIP` already contains the full spine + hardening + focused tests
  (19 files, 2145+/402-, `git diff --check` clean at push time). Verify on fetch:
  `git diff --check 5fe145e5..f9192055` must exit 0 and
  `git rev-parse origin/clean/gemma4-tools-minimal` must equal the value above.
- Upstream has moved past the pinned base (`a114cfa8` #4431 exists on `upstream/main`).
  **Base stays `5fe145e5` for THIS session** (the clean port is built and verified against it).
  Do not rebase onto `a114cfa8`. Record the drift in your report; the rebase is future work.
- The 5 parser-hardening commits inside the clean tip (for traceability, newest-last):
  `5078fa8c` (boundaries/guard), `d34b222a` + `8521ad89` (bare-call pair),
  `d7b594bf` (lossless-numbers pair), `26bf7fbf` (fail-closed flush).

## 3. Build the integration branch (exact recipe)

```powershell
git rev-parse --verify integration/gemma4-local-acceptance-2026.4
# must FAIL (branch must not exist). If it exists -> STOP, report, do not touch it.
git checkout -b integration/gemma4-local-acceptance-2026.4 f919205576f9278d96071eed9e419da0c4fdc15f
git log --oneline -1   # must be f9192055
git status --short     # must be clean (except ignored build dirs)
```

## 4. Allowed deltas on the integration branch (closed list)

You may add commits touching ONLY these paths:

- `src/test/llm/gemma4_fast/**` (parser gate wiring, if needed)
- `src/test/llm/generation_config/**` (generation/policy gate wiring, if needed)
- `src/test/llm/output_parsers/gemma4_v2_contract_test.cpp` (already present; do not duplicate)
- Harness/unit helpers UNDER `src/test/**` strictly required by the §5 commands
- `docs/superpowers/plans/2026-09-07-gemma4-local-acceptance-execution-session.md` (this file; notes only)
- Windows-runner readiness checklist file (new, docs only — see §5.5)

ABSOLUTELY FORBIDDEN on this branch:

- Any production change under `src/llm/**`, `src/BUILD`, `src/llm/BUILD`
  (parser, generator, plumbing and the Responses 1-liner are FROZEN at `f9192055`).
- `ab-evidence/**`, runtime dumps, `HANDOFF.md`-style docs, `servable*`, chat-template,
  `py_jinja*`, reasoning-parser changes, session transport, fast-build scripts,
  `kfs_rest_test`, `max_model_length_test`, `multi_part_parser_drogon_test` edits.
- `git merge` (of anything), force-push, PR creation, `main` checkouts for editing.

**Fix protocol.** If a gate fails for a production root cause: fix it in a NEW commit
on the integration branch with message `fix(gemma4-acceptance): <one line> + Source: <origin commit or NEW>`,
re-run ALL gates from §5 from scratch, and the resulting HEAD becomes the new `TEST_SHA`
candidate. Never amend or rewrite pushed history. If the fix needs a semantic decision
not present in the clean-port plan (AUTO=native, session transport, new grammar shape) → STOP (§8).

## 5. The four gates + runner readiness (exact commands)

Run on the integration branch, from the repo root. Record stdout/stderr tail + exit code per gate.
`PASS` requires exit 0 AND the named tests actually executed (not skipped, not filtered to zero).

### 5.1 PARSER_TEST

```powershell
bazel test //src/test/llm/gemma4_fast:gemma4_parser_contract_test
```

Covers `gemma4_parser_contract_test.cpp` + `gemma4_parser_hardening_test.cpp`
(boundaries, lossless numbers, bare-call recovery, fail-closed flush, Windows-path fidelity).
Tokenizer-gated cases need a Gemma tokenizer (`GEMMA4_TOKENIZER_PATH`); if absent → `BLOCKED`, not `PASS`.

### 5.2 GENERATION_TEST

```powershell
bazel test //src/test/llm/generation_config:gemma4_generation_contract_test
```

Covers AUTO `TriggeredTags`, Hard `TagsWithSeparator` + required-thought Union,
Gemma-only fail-closed vs generic fallback, `stop_after_first = !parallelToolCalls`.
Needs a tokenizer for grammar validation; if the pinned GenAI headers lack
`stop_after_first` (compile error) → STOP with exact compiler evidence (§8.3).

### 5.3 OPENAI_POLICY_TEST

```powershell
bazel test //src/test/llm/generation_config:openai_parallel_tool_calls_contract_test
```

Covers absent→true / true→true / false→false / non-bool→InvalidArgument for
chat-completions AND responses, plus `serializeUnaryResponse` echoing the policy
(the `34c2f23d` 1-liner). Uses the `facebook/opt-125m` tokenizer fixture only.

### 5.4 HARNESS_UNIT_TESTS

```powershell
bazel test //src:ovms_test --test_filter='Gemma4V2ContractTest.*:Gemma4OutputParserTest.*'
```

Covers the v2 end-to-end parser contract (auto-globbed `gemma4_v2_contract_test.cpp`)
plus the upstream Gemma4 parser regression suite. Needs the Gemma tokenizer
(`src/test/llm_testing/OpenVINO/gemma-4-E4B-it-int4-ov` or `GEMMA4_TOKENIZER_PATH`);
if absent → `BLOCKED`, not `PASS`. Zero-test-executed (bad filter) counts as `FAIL` —
verify the run actually executed both suites.

### 5.5 WINDOWS_RUNNER_READY (checklist, no execution here)

Set `YES` only if ALL hold (otherwise `NO` + reason):

- [ ] `build-windows.ps1` invocation written down with pinned args
      (`-ModelServerPath <tree> -DependenciesRoot opt -DeployTo C:\llm\ovms-gemma4-patched`,
      `-VisualStudioPath` discovery via real `cl.exe`, `-InstallDependencies` only if `C:\opt` incomplete)
- [ ] Launch parameters recorded (`vlm-stable`, `JINJA`, REST 8000, `PYTHONHOME`=deployed `python\`)
- [ ] Smoke + probe commands recorded
      (`smoke_tool_call.py --base-url http://127.0.0.1:8000 --model gemma4-26-heretic --mode all`,
      17-case probe, NovaClaw later-turn, TRACE first-token-48 capture)
- [ ] `Gemma4OutputParserTest.*` + `ovms.exe --version` listed as build-time gates

No live claim is made in this session: `LOCAL_WINDOWS_ACCEPTANCE: NOT_RUN`, always.

## 6. TEST_SHA, push, report

1. `TEST_SHA` = `git rev-parse HEAD` on `integration/gemma4-local-acceptance-2026.4`
   AFTER all §5 gates are green (live excluded). If zero new commits were needed,
   `TEST_SHA` equals `f9192055` — that is a valid outcome, state it explicitly.
2. Push (no force, no PR):
   `git push origin integration/gemma4-local-acceptance-2026.4`
   then verify `git ls-remote origin integration/gemma4-local-acceptance-2026.4` matches.
3. Final report — EXACTLY this block, no paraphrase of field names:

```text
INTEGRATION_BRANCH:
integration/gemma4-local-acceptance-2026.4

TEST_SHA:
<40-char exact SHA>

PARSER_TEST:
PASS | FAIL | BLOCKED | NOT_RUN

GENERATION_TEST:
PASS | FAIL | BLOCKED | NOT_RUN

OPENAI_POLICY_TEST:
PASS | FAIL | BLOCKED | NOT_RUN

HARNESS_UNIT_TESTS:
PASS | FAIL | BLOCKED | NOT_RUN

WINDOWS_RUNNER_READY:
YES | NO

LOCAL_WINDOWS_ACCEPTANCE:
NOT_RUN

MAINTAINER_PR_SOURCE:
NO
```

Append after the block: per-gate command + exit code + evidence line (log tail),
`git diff --check` result, full `git log --oneline 5fe145e5..TEST_SHA`,
`git diff --stat 5fe145e5..TEST_SHA`, and confirmation that no forbidden path changed.

## 7. STOP conditions (do not improvise past these)

- `integration/gemma4-local-acceptance-2026.4` already exists on origin → STOP, report.
- No Bazel / no toolchain in your environment → all build gates `BLOCKED`, still push
  nothing, report with evidence (this is a valid session outcome, not a failure to hide).
- `stop_after_first` (or any GenAI symbol) missing from pinned headers → STOP with exact
  compile evidence. Do NOT write compatibility shims around it.
- Upstream `main` moved again → record, keep base `5fe145e5`, continue; rebase is out of scope.
- Any required change outside §4 (new semantics, AUTO=native per open PR #6,
  session transport, template changes) → STOP and bring it to review with the exact diff hunk.
- `git diff --check` non-zero, dirty tree, or any forbidden-path delta → fix or STOP, never push.

## 8. Downstream reference (do NOT execute; context only)

After this session, `TEST_SHA` moves to the Windows Arc/Gemma4 machine, which builds that
EXACT sha and runs live acceptance. Proposed gate mapping (Windows session freezes it):

- G1 `auto` still returns structured tool calls where it did before
- G2 `tool_choice=none` stays tool-free
- G3 `tool_choice=required` emits a structured call with no preceding prose
- G4 conflicting named `get_weather` enforced over the arithmetic prompt
- G5 guided standard JSON + native `<|"|>` args both valid OpenAI JSON; nested types kept
- G6 streaming `delta.tool_calls` + `finish_reason=tool_calls`, no markup leak
- G7 TRACE proves hard choice begins with token 48 (`<|tool_call>`)

`NOT_LOCAL_ACCEPTED` → fix → new `TEST_SHA` (new session).
`LOCAL_ACCEPTED` → `MAINTAINER_PR_SOURCE: YES` → minimal upstream PRs (sketch):
PR1 parser hardening · PR2 generator AUTO/Hard · PR3 parallel policy + Responses fix ·
PR4 focused regression tests. Session/template, evidence and harness stay out of all four.
