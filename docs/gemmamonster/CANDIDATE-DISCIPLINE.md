# Gemmamonster Candidate Discipline

**Purpose:** prevent branch confusion, unverifiable binaries, and unsupported known-good claims while Gemmamonster parser/generator work moves through source, build, protocol, and live acceptance gates.

This document is deliberately boring. Boring is what keeps a local inference stack from becoming a folklore exhibit.

## 1. Branch lanes

Use stable branch prefixes with non-overlapping meaning:

| Lane | Meaning | Promotion rule |
| --- | --- | --- |
| `main` | ordinary repository mainline | never updated by experimental scripts |
| `integration/gemma4-parser-generator-refit-next` | source-level integration candidate | only receives reviewed source changes |
| `test/gemmamonster-gateXX-YYYYMMDD-<base>` | build/test work branch | may be rewritten by local test agents only by explicit request |
| `infra/gemmamonster-*` | repository tooling and evidence discipline | reviewed separately from parser runtime changes |
| `freeze/gemmamonster-YYYYMMDD-known-good-<sha>` | accepted runtime source point | only after evidence bundle and live acceptance |
| `scratch/<agent>/<topic>-<date>` | throwaway exploration | never merge directly into integration |

Flow is one-way:

```text
test/scratch -> integration -> freeze
```

Do not promote diagonally. Diagonal promotion is where branches go to become ghost stories.

## 2. Candidate identity

A candidate is not a branch and not a random `ovms.exe` found under `bazel-bin`. A candidate is a manifest-backed tuple:

```text
source_sha
tree_sha
branch
repo_dirty=false unless explicitly marked
build_profile
build_command
binary_path
binary_sha256
candidate_dir
test_summary_path
test_overall
model_path_or_revision when launched
launch_profile when launched
acceptance_status
```

No manifest means no candidate.
No binary hash means no runtime claim.
No test summary means no test claim.
No evidence bundle means no known-good claim.

## 3. Artifact layout

Default local vault:

```text
C:\gemmamonster-artifacts\candidates\
  <short_sha>-<label>-<timestamp>\
    ovms.exe
    manifest.json
    sha256sums.txt
    build.log
    legacy-candidate.json
    static-audit.json
    runtime-provenance.json
    protocol-runner.log
    protocol-summary.json
    runtime\
      <timestamp>\
        launch.json
        ovms.stdout.log
        ovms.stderr.log
        healthcheck.json
```

The vault is intentionally outside the repo by default. Build outputs are large machine artifacts, not source history. The repo stores rules and acceptance reports, not a museum of binaries.

## 4. Candidate statuses

Use these statuses exactly:

| Status | Meaning |
| --- | --- |
| `source_only` | source ref exists, no build evidence |
| `built_not_accepted` | binary exists and hash is recorded, tests not accepted |
| `protocol_pass` | required protocol tests passed for this exact source/binary context |
| `live_pass` | live OVMS REST acceptance passed for this exact candidate |
| `known_good` | candidate has bundle, logs, binary hash, source SHA, model/runtime details |
| `rejected` | candidate failed or was superseded |

Do not call `built_not_accepted` a release candidate. It is a compiled suspicion.

## 5. Build wrapper contract

Use:

```powershell
.\scripts\gemmamonster\build-candidate.ps1 -RepoRoot . -Label gate12 -RunProtocol
```

The wrapper must:

1. resolve current branch, source SHA, and tree SHA;
2. refuse dirty source unless `-AllowDirty` is passed;
3. invoke `scripts/gemma4/build-local-candidate.ps1`;
4. copy the resulting `ovms.exe` to the candidate vault;
5. compute and record `ovms.exe` SHA256;
6. write `manifest.json`;
7. optionally run protocol tests and copy the newest protocol summary;
8. print `SOURCE_SHA`, `BINARY_SHA256`, `MANIFEST`, and `STATUS`.

## 6. Launch wrapper contract

Use:

```powershell
.\scripts\gemmamonster\launch-candidate.ps1 `
  -CandidateDir C:\gemmamonster-artifacts\candidates\<candidate> `
  -ModelPath C:\llm\models\OpenVINO\Wondernuttz\gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov `
  -ModelName gemma4-26-heretic `
  -RestPort 8000
```

The launcher must refuse to run when:

- `manifest.json` is missing;
- `ovms.exe` is missing;
- binary SHA256 differs from the manifest;
- model path is missing;
- requested REST port is already occupied.

Every launch writes `runtime/<timestamp>/launch.json` with PID, binary hash, source SHA, command line, model path, port, and timestamp.

## 7. Promotion gate

Use:

```powershell
.\scripts\gemmamonster\promote-candidate.ps1 `
  -CandidateManifest C:\gemmamonster-artifacts\candidates\<candidate>\manifest.json `
  -RepoRoot . `
  -DryRun
```

The gate must reject promotion unless:

- manifest exists and parses;
- binary hash matches;
- source SHA is present;
- protocol summary exists and says `PASS`;
- build log exists;
- candidate status is at least `protocol_pass` unless `-DryRun` is used.

The promotion script may generate an acceptance report scaffold under `docs/gemmamonster/acceptance/`, but it must not move protected branches or tags automatically.

## 8. Agent handoff block

Every agent working on candidates must return this block:

```text
BRANCH:
BASE_SHA:
HEAD_SHA:
COMMITS:
FILES_CHANGED:
BUILD:
TESTS:
KNOWN_FAILURES:
ARTIFACTS:
BUNDLE_SHA256:
PROMOTION_RECOMMENDATION:
```

Allowed evidence words:

```text
PASS: command exited 0, log path given
FAIL: command exited nonzero, first failing test/log given
NOT_RUN: reason given
UNKNOWN: evidence missing
```

Forbidden optimism:

```text
gотово
вроде работает
почти зелёное
не должно ломать
тесты проходили где-то там
```

## 9. Current policy for Gemmamonster Gate 1/2

For the current `e398363c2fe6f572a0fdc3ed9fd37c551fd73c76` source point:

- Jinja contract is wired at source level.
- Content-owned boundary routing semantic port is present at source level.
- Target branch has not yet produced machine-verification evidence.
- Source-branch results from `671f84c25...` do not certify this target branch.

Minimum target checks before promotion:

```powershell
bazel test //src:llm_output_parser_tests
bazel test //src/test/llm/gemma4_overlay:gemma4_google_jinja_contract_test
bazel test //src/test/llm/gemma4_overlay:gemma4_chat_template_overlay_contract_test
bazel test //src/test/llm/generation_config:gemma4_generation_contract_test
.\scripts\gemma4\test-protocol-hardening.ps1 -RepoRoot . -BuildFirst
```

A Devstral tokenizer failure caused only by absent `openvino_tokenizer.xml` must be recorded as known unrelated, not as Gemma4 acceptance failure.
