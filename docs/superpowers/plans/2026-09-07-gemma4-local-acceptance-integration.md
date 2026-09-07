# Gemma4 Local Acceptance Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce one exact `integration/gemma4-local-acceptance-2026.4` source ref that combines the current Gemma4 generation/API spine with the five parser-hardening commits, passes all available offline contracts, and can be built and exercised on the Windows Gemma4 machine through one provenance-bound acceptance run.

**Architecture:** Start from the exact `fix/gemma4-responses-parallel-tool-policy` spine and replay only the five parser-hardening commits unique to `fix/gemma4-parser-hardening-post-f36d2d75`. Runtime code changes are allowed only when a contract test exposes a gap. Acceptance tooling is layered separately under `ab-evidence`: a fail-closed aggregator, the existing chained-session harness, and a Windows runner bind build identity, source SHA, binary SHA256, and G1-G7 results into one final verdict.

**Tech Stack:** C++17, OpenVINO Model Server 2026.4 lineage, OpenVINO GenAI `StructuredOutputConfig`, xgrammar, RapidJSON, GoogleTest, Bazel, Python 3 standard library, Windows PowerShell.

**Spec:** `docs/superpowers/specs/2026-09-07-gemma4-local-acceptance-integration-gate-design.md`

## Global Constraints

- Re-resolve every pinned ref immediately before implementation. Branch movement is a new planning input, never an implicit substitution.
- Design-freeze spine: `34c2f23d58e96a2c2ef1b3e2f940909c3131ace5` on `fix/gemma4-responses-parallel-tool-policy`.
- Design-freeze parser source: `d1c21ac1a54d499e644e7619155944a3875fd071` on `fix/gemma4-parser-hardening-post-f36d2d75`.
- Design-freeze common base: `f36d2d758264ac5f371c344c49e485f582b07b5a`.
- Live regression baseline: `81ff2f2cae8b79cc22f7103cf4c29eb1953f9789`; it is an ancestor baseline, not transferable PASS evidence.
- Upstream comparison reference at design freeze: `a114cfa8ed64e72337a83f55a018c1f8b0c65f0b`; do not rebase the local candidate onto upstream during this integration session.
- Do not move fork `main`, upstream refs, tags, releases, or historical evidence refs.
- Do not merge `fix/gemma4-opencode-auto-tool-native` wholesale. Port only a missing behavior after a RED test proves the current spine lacks it.
- Any required result other than literal `PASS`, including `BLOCKED_BY_PLATFORM`, `NOT_RUN`, `ERROR`, missing evidence, or `FAIL`, yields `NOT_LOCAL_ACCEPTED`.
- Runtime provenance must separate actual `source_sha` and `binary_sha256` from historical/grounding fixture identifiers.
- Historical evidence is immutable and cannot be relabeled as evidence for the new candidate.

---

### Task 1: Re-resolve refs and create the isolated candidate worktree

**Files:**
- Create: `ab-evidence/local-acceptance-source.json`

**Interfaces:**
- Consumes: origin spine/parser refs and upstream `main`.
- Produces: `integration/gemma4-local-acceptance-2026.4` starting from the exact resolved spine and a provenance record with the actual resolved SHAs.

- [ ] **Step 1: Fetch and resolve authority refs**

```bash
git fetch origin --prune
git fetch upstream main
SPINE=$(git rev-parse origin/fix/gemma4-responses-parallel-tool-policy^{commit})
PARSER=$(git rev-parse origin/fix/gemma4-parser-hardening-post-f36d2d75^{commit})
BASE=$(git merge-base "$SPINE" "$PARSER")
UPSTREAM=$(git rev-parse upstream/main^{commit})
LIVE_BASELINE=81ff2f2cae8b79cc22f7103cf4c29eb1953f9789
printf 'SPINE=%s\nPARSER=%s\nBASE=%s\nUPSTREAM=%s\n' "$SPINE" "$PARSER" "$BASE" "$UPSTREAM"
```

At design freeze the output was:

```text
SPINE=34c2f23d58e96a2c2ef1b3e2f940909c3131ace5
PARSER=d1c21ac1a54d499e644e7619155944a3875fd071
BASE=f36d2d758264ac5f371c344c49e485f582b07b5a
UPSTREAM=a114cfa8ed64e72337a83f55a018c1f8b0c65f0b
```

If any value differs, record the actual output and stop before branch creation for a compare/review of the moved ref.

- [ ] **Step 2: Prove ancestry assumptions**

```bash
git merge-base --is-ancestor "$BASE" "$SPINE"
git merge-base --is-ancestor "$BASE" "$PARSER"
git merge-base --is-ancestor "$LIVE_BASELINE" "$SPINE"
test "$(git merge-base "$SPINE" "$PARSER")" = "$BASE"
```

Expected: all commands exit 0.

- [ ] **Step 3: Create an isolated worktree and candidate branch**

```bash
git worktree add ../model_server-gemma4-local-acceptance \
  -b integration/gemma4-local-acceptance-2026.4 "$SPINE"
cd ../model_server-gemma4-local-acceptance
test "$(git rev-parse HEAD)" = "$SPINE"
```

- [ ] **Step 4: Write resolved-source provenance without hard-coding guessed values**

```bash
python - "$SPINE" "$PARSER" "$BASE" "$UPSTREAM" "$LIVE_BASELINE" <<'PY'
import json, pathlib, sys
spine, parser, base, upstream, live = sys.argv[1:]
out = {
    "schema_version": 1,
    "candidate_branch": "integration/gemma4-local-acceptance-2026.4",
    "integration_spine_sha": spine,
    "parser_source_sha": parser,
    "common_base_sha": base,
    "upstream_reference_sha": upstream,
    "live_regression_baseline_sha": live,
}
path = pathlib.Path("ab-evidence/local-acceptance-source.json")
path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
PY
```

- [ ] **Step 5: Commit the provenance record**

```bash
git add ab-evidence/local-acceptance-source.json
git commit -m "test(gemma4): pin local acceptance integration inputs"
```

---

### Task 2: Replay the five parser-hardening commits in verified order

**Files:**
- Modify by replay: `src/llm/io_processing/gemma4/gemma4_tool_parser.cpp`
- Modify by replay: `src/llm/io_processing/gemma4/gemma4_tool_parser.hpp`
- Modify by replay: `src/test/llm/gemma4_fast/BUILD`
- Create by replay: `src/test/llm/gemma4_fast/gemma4_parser_hardening_test.cpp`
- Modify by replay: `ab-evidence/reliability_grounded_harness_v2.py`
- Modify by replay: `ab-evidence/test_reliability_grounded_harness_v2.py`

**Interfaces:**
- Produces parser contracts for lexical-number preservation, bounded bare calls, Windows path fidelity, fail-closed JSON output, and unambiguous runtime provenance.

Expected parser-only commit order from the frozen common base:

```text
149c8e1b7d5c36dd3d62cb0c0fae1c217d6a7c4a  fix(gemma4): validate lossless native numbers before raw emission
1598c3d68c652c35cab0af3c3c695f8b54365e43  fix(gemma4): bound bare-call recovery and preserve incomplete prose
18ad1514a97eafcd9be31cd9d9cfbaa09e1d4343  test(gemma4): lock Windows path argument fidelity
aa110ba01a78ed9583507024f7492f05021925a2  test(gemma4): enforce fail-closed parser output invariants
d1c21ac1a54d499e644e7619155944a3875fd071  test(gemma4): separate runtime provenance from grounding fixtures
```

- [ ] **Step 1: Verify the actual replay list**

```bash
git log --reverse --format='%H %s' "$BASE"..origin/fix/gemma4-parser-hardening-post-f36d2d75
```

Expected: exactly the five commits above. Stop if there are more, fewer, reordered, or replaced commits.

- [ ] **Step 2: Replay lossless-number validation and run focused tests**

```bash
git cherry-pick 149c8e1b7d5c36dd3d62cb0c0fae1c217d6a7c4a
bazel test //src/test/llm/gemma4_fast:gemma4_parser_contract_test \
  --test_filter='Gemma4ParserHardeningTest.MalformedNumericLookingScalarsDoNotEmitInvalidJson:Gemma4ParserHardeningTest.ValidLargeJsonNumbersStayLexicallyLossless'
```

Expected: PASS.

- [ ] **Step 3: Replay bounded bare-call recovery and run focused tests**

```bash
git cherry-pick 1598c3d68c652c35cab0af3c3c695f8b54365e43
bazel test //src/test/llm/gemma4_fast:gemma4_parser_contract_test \
  --test_filter='Gemma4ParserHardeningTest.IncompleteBareCallsRemainVisibleContentAtFinish:Gemma4ParserHardeningTest.FragmentedBareCallProseDoesNotDisappear:Gemma4ParserHardeningTest.CompleteBareAndCanonicalControlsStillParse'
```

Expected: PASS.

- [ ] **Step 4: Replay Windows-path fidelity and run its focused test**

```bash
git cherry-pick 18ad1514a97eafcd9be31cd9d9cfbaa09e1d4343
bazel test //src/test/llm/gemma4_fast:gemma4_parser_contract_test \
  --test_filter=Gemma4ParserHardeningTest.PreservesWindowsPathArgumentsByteForByte
```

Expected: PASS.

- [ ] **Step 5: Replay fail-closed output invariants and run the invariant corpus**

```bash
git cherry-pick aa110ba01a78ed9583507024f7492f05021925a2
bazel test //src/test/llm/gemma4_fast:gemma4_parser_contract_test \
  --test_filter=Gemma4ParserHardeningTest.ParserOutputJsonValidityInvariantCorpus
```

Expected: PASS.

- [ ] **Step 6: Replay provenance separation and run the Python contract tests**

```bash
git cherry-pick d1c21ac1a54d499e644e7619155944a3875fd071
(
  cd ab-evidence
  python -m unittest test_reliability_grounded_harness_v2.py
)
```

Expected: exit 0.

- [ ] **Step 7: Run the complete parser target after replay**

```bash
bazel test //src/test/llm/gemma4_fast:gemma4_parser_contract_test
```

Expected: exit 0 with zero failed tests.

---

### Task 3: Prove the inherited generation and OpenAI policy spine before changing runtime code

**Files:**
- Verify and modify only on RED: `src/llm/io_processing/base_generation_config_builder.hpp`
- Verify and modify only on RED: `src/llm/io_processing/generation_config_builder.hpp`
- Verify and modify only on RED: `src/llm/apis/openai_request.hpp`
- Verify and modify only on RED: `src/llm/apis/openai_api_handler.hpp`
- Verify and modify only on RED: `src/llm/apis/openai_completions.hpp`
- Verify and modify only on RED: `src/llm/apis/openai_responses.hpp`
- Verify and modify only on RED: `src/llm/apis/openai_responses.cpp`
- Test: `src/test/llm/generation_config/gemma4_generation_contract_test.cpp`
- Test: `src/test/llm/generation_config/openai_parallel_tool_calls_contract_test.cpp`

**Interfaces:**
- Must preserve `none`, lazy-capable `auto`, mandatory `required`, named choice, nested schema fidelity, hard-choice fail-closed validation, and `parallel_tool_calls` policy.

- [ ] **Step 1: Run all Gemma4 generation contracts**

```bash
bazel test //src/test/llm/generation_config:gemma4_generation_contract_test
```

Expected: PASS. The target already covers `TriggeredTags` auto behavior, mandatory hard choices, reasoning-before-tool branches, nested schemas, invalid tool names/schemas, and `parallel_tool_calls` repeatability.

- [ ] **Step 2: Run OpenAI policy contracts**

```bash
bazel test //src/test/llm/generation_config:openai_parallel_tool_calls_contract_test
```

Expected: PASS for the represented Chat Completions and Responses policy conversions.

- [ ] **Step 3: Compare the old native-auto branch only for missing behavior**

```bash
git show origin/fix/gemma4-opencode-auto-tool-native:src/llm/io_processing/generation_config_builder.hpp > old-gemma4-generation.hpp
grep -n 'auto\|toolChoice\|structured_output' old-gemma4-generation.hpp | head -80
grep -n 'TriggeredTags\|AutoUsesTriggeredToolGrammar\|parallelToolCalls' \
  src/llm/io_processing/generation_config_builder.hpp \
  src/test/llm/generation_config/gemma4_generation_contract_test.cpp
rm old-gemma4-generation.hpp
```

If an old behavior is not represented by current tests, first add a RED test to `gemma4_generation_contract_test.cpp`, then implement the minimum fix. Do not merge the old branch.

- [ ] **Step 4: If a RED gap exists, close it with TDD and a narrow commit**

Example required cycle:

```bash
bazel test //src/test/llm/generation_config:gemma4_generation_contract_test --test_filter=Gemma4GenerationContractTest.NewlyNamedRegression
# verify FAIL
git add src/test/llm/generation_config/gemma4_generation_contract_test.cpp src/llm/io_processing/generation_config_builder.hpp
git commit -m "fix(gemma4): close local acceptance generation contract gap"
bazel test //src/test/llm/generation_config:gemma4_generation_contract_test
```

If no RED gap exists, create no runtime commit in this task.

---

### Task 4: Add the fail-closed local acceptance aggregator

**Files:**
- Create: `ab-evidence/local_acceptance_gate.py`
- Create: `ab-evidence/test_local_acceptance_gate.py`
- Create: `ab-evidence/local-acceptance-cases.json`

**Interfaces:**
- Produces `REQUIRED_CASES`, `aggregate_verdict(case_results)`, JSON load/write helpers, and CLI command `finalize`.
- `finalize` consumes a run directory, source SHA, binary SHA256, and case spec; it writes `summary.json` and returns non-zero unless the verdict is `LOCAL_ACCEPTED`.

- [ ] **Step 1: Write RED unit tests**

Create `ab-evidence/test_local_acceptance_gate.py`:

```python
import unittest
import local_acceptance_gate as gate


class LocalAcceptanceGateTests(unittest.TestCase):
    def test_all_required_pass(self):
        results = {name: "PASS" for name in gate.REQUIRED_CASES}
        self.assertEqual(gate.aggregate_verdict(results), "LOCAL_ACCEPTED")

    def test_any_non_pass_fails_closed(self):
        for verdict in ("FAIL", "ERROR", "NOT_RUN", "BLOCKED_BY_PLATFORM"):
            with self.subTest(verdict=verdict):
                results = {name: "PASS" for name in gate.REQUIRED_CASES}
                results[gate.REQUIRED_CASES[0]] = verdict
                self.assertEqual(gate.aggregate_verdict(results), "NOT_LOCAL_ACCEPTED")

    def test_missing_required_case_fails_closed(self):
        results = {name: "PASS" for name in gate.REQUIRED_CASES[1:]}
        self.assertEqual(gate.aggregate_verdict(results), "NOT_LOCAL_ACCEPTED")
```

- [ ] **Step 2: Verify RED**

```bash
(
  cd ab-evidence
  python -m unittest test_local_acceptance_gate.py
)
```

Expected: import/module failure because the implementation does not yet exist.

- [ ] **Step 3: Implement the minimum public contract**

Create `ab-evidence/local_acceptance_gate.py` with these exact required case IDs:

```python
REQUIRED_CASES = (
    "build",
    "parser",
    "auto_prose",
    "auto_tool",
    "auto_invalid_tool",
    "required",
    "required_fail_closed",
    "named",
    "named_wrong_tool",
    "stream_split_tag",
    "stream_split_nested_arguments",
    "multi_call",
    "chained_session",
    "responses_policy",
    "invalid_structured_config",
    "live_gemma4",
)


def aggregate_verdict(case_results):
    if any(case_results.get(name) != "PASS" for name in REQUIRED_CASES):
        return "NOT_LOCAL_ACCEPTED"
    return "LOCAL_ACCEPTED"
```

Implement `finalize` so its output always includes `source_sha`, `binary_sha256`, `cases`, and `verdict`; missing case files become `NOT_RUN` rather than being ignored.

- [ ] **Step 4: Define G1-G7 mapping in `local-acceptance-cases.json`**

Use one JSON object per `REQUIRED_CASES` ID. Each object contains `id`, `gate`, `required: true`, and a relative evidence path. Map build to G1, parser to G2, generation cases to G3, streaming/multi-call to G4, chained session to G5, Responses policy to G6, and `live_gemma4` to G7.

- [ ] **Step 5: Verify GREEN and commit**

```bash
(
  cd ab-evidence
  python -m unittest test_local_acceptance_gate.py
)
git add ab-evidence/local_acceptance_gate.py ab-evidence/test_local_acceptance_gate.py ab-evidence/local-acceptance-cases.json
git commit -m "test(gemma4): add fail-closed local acceptance gate"
```

Expected: tests exit 0 before commit.

---

### Task 5: Make chained-session evidence directly consumable by the gate

**Files:**
- Modify: `ab-evidence/live_chain_harness.py`
- Create: `ab-evidence/test_live_chain_harness.py`

**Interfaces:**
- Preserve current `--commit-sha`, read-only Git executor, `X-OVMS-Session-ID`, restart/resume checkpoint, and exact SHA propagation semantics.
- Add pure helper `validate_chain_summary(summary, expected_sha, expected_second_choice) -> bool`.

- [ ] **Step 1: Write RED helper tests**

```python
import unittest
import live_chain_harness as chain


class LiveChainSummaryTests(unittest.TestCase):
    def test_valid_summary(self):
        summary = {
            "verdict": "PASS",
            "commit_sha": "a" * 40,
            "second_tool_choice": "required",
            "exact_sha_pass": True,
        }
        self.assertTrue(chain.validate_chain_summary(summary, "a" * 40, "required"))

    def test_stale_sha_is_rejected(self):
        summary = {
            "verdict": "PASS",
            "commit_sha": "b" * 40,
            "second_tool_choice": "required",
            "exact_sha_pass": True,
        }
        self.assertFalse(chain.validate_chain_summary(summary, "a" * 40, "required"))
```

Add equivalent cases for wrong second choice, false `exact_sha_pass`, and non-PASS verdict.

- [ ] **Step 2: Verify RED, implement helper, verify GREEN**

```bash
(
  cd ab-evidence
  python -m unittest test_live_chain_harness.py
)
```

Implement:

```python
def validate_chain_summary(summary, expected_sha, expected_second_choice):
    return (
        summary.get("verdict") == "PASS"
        and summary.get("commit_sha") == expected_sha
        and summary.get("second_tool_choice") == expected_second_choice
        and summary.get("exact_sha_pass") is True
    )
```

Then rerun:

```bash
(
  cd ab-evidence
  python -m unittest test_live_chain_harness.py test_reliability_grounded_harness_v2.py
)
```

Expected: exit 0.

- [ ] **Step 3: Commit harness normalization**

```bash
git add ab-evidence/live_chain_harness.py ab-evidence/test_live_chain_harness.py
git commit -m "test(gemma4): normalize chained-session acceptance evidence"
```

---

### Task 6: Add the Windows exact-SHA acceptance runner

**Files:**
- Create: `ab-evidence/run_gemma4_local_acceptance.ps1`
- Create: `ab-evidence/LOCAL-ACCEPTANCE-WINDOWS.md`

**Interfaces:**
- Script parameters: `RepoRoot`, `ModelPath`, `ModelName`, `RestPort`, `ToolCatalog`, `TokenizerPath`, and repository-specific build command/executable location documented from the existing local OVMS workflow.
- Produces `ab-evidence/local-runs/<8-char-sha>/<UTC timestamp>/` containing source SHA, build output, binary SHA256, per-case evidence, and final `summary.json`.

- [ ] **Step 1: Fail before build unless the checkout is exact and clean**

PowerShell start-of-run contract:

```powershell
Set-Location $RepoRoot
$SourceSha = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $SourceSha -notmatch '^[0-9a-f]{40}$') { throw 'Cannot resolve source SHA' }
$Dirty = git status --porcelain
if ($Dirty) { throw 'Candidate worktree must be clean' }
$RunId = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$RunDir = Join-Path $RepoRoot ("ab-evidence/local-runs/{0}/{1}" -f $SourceSha.Substring(0,8), $RunId)
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$SourceSha | Set-Content -Encoding ascii (Join-Path $RunDir 'source-sha.txt')
```

- [ ] **Step 2: Build the same checkout that will be tested**

Invoke the repository's existing Windows build entry point used on the Gemma4 machine. Record the exact command to `build-command.txt`, full stdout/stderr to `build-output.txt`, and do not launch OVMS on a non-zero build exit.

After build success:

```powershell
$BinaryHash = (Get-FileHash -Algorithm SHA256 $OvmsExe).Hash.ToLowerInvariant()
$BinaryHash | Set-Content -Encoding ascii (Join-Path $RunDir 'binary-sha256.txt')
```

- [ ] **Step 3: Run offline contract gates before server launch**

The runner invokes the Windows equivalents of:

```text
//src/test/llm/gemma4_fast:gemma4_parser_contract_test
//src/test/llm/generation_config:gemma4_generation_contract_test
//src/test/llm/generation_config:openai_parallel_tool_calls_contract_test
python -m unittest test_reliability_grounded_harness_v2.py test_local_acceptance_gate.py test_live_chain_harness.py
```

Capture command, exit code, stdout and stderr for each. Any required offline failure stops the run before live inference.

- [ ] **Step 4: Run the complete live matrix in one run directory**

The runner must produce evidence for:

```text
auto_prose
auto_tool
auto_invalid_tool
required
required_fail_closed
named
named_wrong_tool
stream_split_tag
stream_split_nested_arguments
multi_call
chained_session with restart/resume
responses_policy
invalid_structured_config
live_gemma4
```

For chained-session cases call `live_chain_harness.py` with the actual `$SourceSha`. Existing live witness files may be used as fixture/reference inputs only, never as the result of the new run.

- [ ] **Step 5: Finalize through the Python gate**

```powershell
python ab-evidence/local_acceptance_gate.py finalize `
  --case-spec ab-evidence/local-acceptance-cases.json `
  --run-dir $RunDir `
  --source-sha $SourceSha `
  --binary-sha256 $BinaryHash
if ($LASTEXITCODE -ne 0) { throw 'Local acceptance gate failed' }
```

The finalizer, not ad hoc PowerShell conditions, owns the final verdict.

- [ ] **Step 6: Document one copy-paste operator command with real parameter provenance**

`LOCAL-ACCEPTANCE-WINDOWS.md` must explain where each required parameter value comes from on the target machine, including the current model path/name, REST port, tool catalog, tokenizer path, build entry point and produced `ovms.exe` path. Do not insert unexplained `TBD` or `TODO` markers.

- [ ] **Step 7: Commit runner and runbook**

```bash
git add ab-evidence/run_gemma4_local_acceptance.ps1 ab-evidence/LOCAL-ACCEPTANCE-WINDOWS.md
git commit -m "test(gemma4): add exact-sha Windows local acceptance runner"
```

---

### Task 7: Fresh offline verification and publication of exactly one TEST_SHA

**Files:**
- No new runtime file is required in this task.

**Interfaces:**
- Produces: one pushed `TEST_SHA` whose tree is exactly what the Windows runner must build and test.

- [ ] **Step 1: Run all C++ contract targets fresh**

```bash
bazel test //src/test/llm/gemma4_fast:gemma4_parser_contract_test
bazel test //src/test/llm/generation_config:gemma4_generation_contract_test
bazel test //src/test/llm/generation_config:openai_parallel_tool_calls_contract_test
```

Expected: all exit 0 with zero failed tests.

- [ ] **Step 2: Run all acceptance-tool Python tests fresh**

```bash
(
  cd ab-evidence
  python -m unittest \
    test_reliability_grounded_harness_v2.py \
    test_local_acceptance_gate.py \
    test_live_chain_harness.py
)
```

Expected: exit 0.

- [ ] **Step 3: Verify cleanliness and ancestry**

```bash
test -z "$(git status --porcelain)"
TEST_SHA=$(git rev-parse HEAD)
RECORDED_SPINE=$(python -c 'import json; print(json.load(open("ab-evidence/local-acceptance-source.json"))["integration_spine_sha"])')
git merge-base --is-ancestor "$RECORDED_SPINE" "$TEST_SHA"
git merge-base --is-ancestor 81ff2f2cae8b79cc22f7103cf4c29eb1953f9789 "$TEST_SHA"
printf 'TEST_SHA=%s\n' "$TEST_SHA"
```

Expected: clean tree, both ancestry checks exit 0, one literal 40-character TEST_SHA printed.

- [ ] **Step 4: Push the integration branch without adding a self-referential manifest commit**

```bash
git push -u origin integration/gemma4-local-acceptance-2026.4
```

The pushed branch head after this command is the TEST_SHA. Do not commit a file claiming to contain its own commit SHA. Runtime evidence will record TEST_SHA after checkout, where self-reference is no longer a problem.

---

### Task 8: Run Windows local acceptance and promote only the tested source SHA

**Files:**
- Runtime output: `ab-evidence/local-runs/<8-char-sha>/<UTC timestamp>/`
- After the run, optionally commit small textual evidence/report files, but never redefine the tested source SHA.

**Interfaces:**
- Consumes: literal TEST_SHA printed in Task 7.
- Produces: `LOCAL_ACCEPTED` or `NOT_LOCAL_ACCEPTED`, source SHA, binary SHA256, and G1-G7 evidence.

- [ ] **Step 1: Checkout the literal TEST_SHA on the local Windows machine**

```powershell
git fetch origin
git checkout --detach $env:GEMMA4_TEST_SHA
if ((git rev-parse HEAD).Trim() -ne $env:GEMMA4_TEST_SHA) { throw 'Wrong test SHA' }
```

Before running this command set `GEMMA4_TEST_SHA` to the literal 40-character value printed by Task 7.

- [ ] **Step 2: Run the Windows wrapper once for the complete matrix**

Use the exact invocation documented by `ab-evidence/LOCAL-ACCEPTANCE-WINDOWS.md`.

A retry is a new complete run directory. Never splice passing cells from separate runs into one synthetic `LOCAL_ACCEPTED` result.

- [ ] **Step 3: Verify final summary identity and verdict**

The resulting `summary.json` must satisfy all of:

```text
source_sha equals GEMMA4_TEST_SHA exactly
binary_sha256 exists and is a 64-character hex digest
every required case is PASS
verdict is LOCAL_ACCEPTED
```

Any `BLOCKED_BY_PLATFORM`, `NOT_RUN`, `ERROR`, `FAIL`, missing case, wrong SHA, or missing binary hash means `NOT_LOCAL_ACCEPTED`.

- [ ] **Step 4: On failure, preserve raw evidence and fix the failing gate on a descendant commit**

Do not call the failed TEST_SHA a Maintainer PR source. A fix produces a new candidate commit and therefore a new TEST_SHA and a new full local run.

- [ ] **Step 5: On full PASS, record the tested SHA explicitly in the report**

A post-test report may be committed later, but it must name the already-tested source SHA and binary hash as data, for example:

```json
{
  "maintainer_pr_source": true,
  "accepted_source_sha": "the literal Task 7 TEST_SHA",
  "accepted_binary_sha256": "the measured Windows binary SHA256",
  "verdict": "LOCAL_ACCEPTED"
}
```

The report commit itself is not the accepted source SHA.

- [ ] **Step 6: Extract Maintainer PRs only after `LOCAL_ACCEPTED`**

Start new upstream-facing branches from then-current upstream `main` and replay minimal patch series in this order:

```text
1. Gemma4 parser correctness and hardening
2. Gemma4 guided-generation semantics
3. streaming/session correctness where independently reviewable
4. Responses/tool-policy fidelity still absent upstream
```

Each Maintainer PR branch must be independently reconciled and tested against the then-current upstream head while citing the accepted integration TEST_SHA and evidence run.

---

## Final verification checklist

Before publishing TEST_SHA for Windows checkout:

```text
[ ] exact refs re-resolved and recorded
[ ] candidate branch starts from recorded spine
[ ] five parser commits replayed in verified order
[ ] full parser target PASS
[ ] full generation target PASS
[ ] OpenAI parallel-policy target PASS
[ ] reliability harness v2 tests PASS
[ ] local acceptance gate tests PASS
[ ] live-chain harness tests PASS
[ ] worktree clean
[ ] candidate remains descendant of recorded spine and 81ff2f2c baseline
[ ] exactly one pushed TEST_SHA named
```

Before declaring `MAINTAINER_PR_SOURCE`:

```text
[ ] Windows build came from TEST_SHA
[ ] binary SHA256 captured
[ ] G1-G7 required evidence belongs to the same run identity
[ ] every required case PASS
[ ] no required case BLOCKED_BY_PLATFORM, NOT_RUN, ERROR, FAIL, or missing
[ ] summary verdict LOCAL_ACCEPTED
[ ] accepted_source_sha equals TEST_SHA exactly
[ ] historical evidence was not substituted for the new run
```
