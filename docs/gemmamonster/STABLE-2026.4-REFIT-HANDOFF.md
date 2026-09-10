# GEMMAMONSTER stable 2026.4 refit build handoff

## Source authority

- Repository: `DassaultFalconKing/model_server`.
- Branch: `integration/gemmamonster-2026.4-latest-refit`.
- Required ancestor: `9eb93f15fecb848d399f17c7a6a6626e5a1498d7`, the latest maintainer OVMS source state before the upstream 2026.5 runtime switch.
- Advanced semantic authority: `fde0762ba314dc5f6448726dfce7c533bad9a8a6` plus the preceding Gemma4 protocol-hardening ancestry.
- Historical provenance authority: the byte-exact `docs/gemmamonster/Bericht-Provenance-Descendance-diff.md` carried from `fde0762`.
- Known-good behavioural/runtime oracle: `freeze/gemmamonster-2026.4-known-good` at `c48366fee1f10cdf6b5fe3c181522ed0c58fc9fd`.

Do not infer completeness from current diff alone. The Bericht provenance union is broader than the current upstream-different file set.

## What is refitted

The current line contains the active Gemma4 protocol/generator blast radius:

- native Gemma4 tool parser and reasoning parser;
- parser-owned tool-call boundaries and generic `OutputParser` routing;
- post-render prompt-state adaptation through chat-template analyzer/adapter/processor;
- special-token reasoning-to-tool streamer handoff;
- guided generation with `TriggeredTags`, hard/named grammar, optional thought-before-tool grammar, fail-closed hard choices, and `parallel_tool_calls` propagation;
- the exact `fde0762` single-tool repeated-call grammar intent;
- OpenAI `parallel_tool_calls` ingress/egress policy;
- fail-closed hard/named `tool_choice` validation when no tools are supplied, preserved through the current header-based policy seam;
- persistent session continuity, carried as an acceptance-critical high-risk slice;
- parser/recovery/streamer, generation/prompt-state, overlay, and OpenAI contracts.

Presence in-tree is not test evidence. Build and test results must be recorded separately.

## Exact runtime profiles

The source branch itself remains pinned to the latest maintainer 2026.4 RC2 values in `versions.mk`.

The build helper supports two exact runtime profiles without editing tracked files:

### `maintainer-rc2`

- OpenVINO: `227c33757d1ef95d4da506d00686f923fdd2a535`
- Tokenizers: `a04accf6282d9b304214b492694b18c3979f667a`
- GenAI: `7ea2546852a382cd16bd22dea0cfad2db70ed744`
- Windows package: `openvino_genai_windows_2026.4.0.0rc2_x86_64.zip`
- default short root: `C:\g54r2`

### `known-good-rc1`

- OpenVINO: `61afcb26271140347709138b13d678e8b1b5925c`
- Tokenizers: `a04accf6282d9b304214b492694b18c3979f667a`
- GenAI: `5f7f1278107d7eae3990ce906bbcfcb69ac3397f`
- Windows package: `openvino_genai_windows_2026.4.0.0rc1_x86_64.zip`
- default short root: `C:\g54r1`

`known-good-rc1` changes only the dependency environment for the build. It does not rewrite `versions.mk`, create a second source branch, or alter the refit source SHA.

## Candidate contract

Never accept a bare `bazel-bin/src/ovms.exe` as a runtime candidate.

The build helper creates:

```text
candidate-root/
├── ovms/
├── ovms.zip
├── manifest.json
├── SHA256SUMS.txt
├── provenance/
│   ├── source.json
│   ├── dependencies.json
│   ├── build.json
│   └── package.json
├── logs/
├── acceptance/
└── dumps/
```

The builder verifies exact dependency-profile pins, restores build-mutated `WORKSPACE` and `src/version.hpp` byte-for-byte, fails if a clean source tree is left dirty, and compares packaged OpenVINO/GenAI/Tokenizers/TBB DLL hashes with the files from which the package was assembled.

The launcher must subsequently prove that loaded runtime modules resolve inside the candidate `ovms/` directory. Module-inspection failure is fatal unless the operator deliberately supplies the unsafe override.

## Pull and pre-build audit

```powershell
cd C:\git\model_server-gemma4-fast

git fetch origin
git switch integration/gemmamonster-2026.4-latest-refit
git reset --hard origin/integration/gemmamonster-2026.4-latest-refit

git rev-parse HEAD
git status --short

.\scripts\gemmamonster\audit-stable-refit.ps1
.\tests\windows\gemmamonster_stable_candidate_contract_test.ps1
```

The source audit must finish with:

```text
BUILD_READY_SOURCE_AUDIT_PASS
```

The candidate-verifier unit contract must finish with:

```text
GEMMAMONSTER_STABLE_CANDIDATE_CONTRACT_TEST_PASS
```

The audit checks exact ancestry, current 2026.4 RC2 source authority, the active runtime blast-radius files, contract files and build-ready helpers. It also requires the exact `fde0762` Bericht when that ref is locally available and records byte-exact versus refitted relations for runtime files.

## Primary build: latest maintainer 2026.4 RC2

For a fresh isolated dependency root, do **not** use `-ExpungeDependencies` on the first run. The upstream installer applies expunge to shared system dependencies under `C:\opt` as well as the short-root package, including MSYS, Bazel, Python/OpenCL/BoringSSL and related build prerequisites.

```powershell
.\scripts\gemmamonster\build-stable-candidate.ps1 `
  -RuntimeProfile maintainer-rc2 `
  -Label gemma4-stable-rc2 `
  -WithoutTests
```

The default dependency root is `C:\g54r2`. The final line must not claim acceptance; the expected state is:

```text
BUILT_PROVENANCE_VERIFIED_NOT_ACCEPTED
```

Record the printed candidate root and source SHA.

Use `-ExpungeDependencies` only to deliberately repair/reinstall a contaminated dependency environment after reviewing the upstream installer's system-wide effects.

## Source contracts

After the RC2 dependencies exist:

```powershell
.\scripts\gemmamonster\test-stable-source.ps1 `
  -RuntimeProfile maintainer-rc2
```

If the tokenizer fixture is not at the repository-default test path, pass it explicitly:

```powershell
.\scripts\gemmamonster\test-stable-source.ps1 `
  -RuntimeProfile maintainer-rc2 `
  -Gemma4TokenizerPath "C:\path\to\gemma4-tokenizer-or-test-model"
```

The runner executes these Bazel targets:

- `//src/test/llm/gemma4_fast:gemma4_parser_contract_test` (this one target compiles/runs parser, reasoning semantic refit, and recovery contract sources together);
- `//src/test/llm/generation_config:gemma4_generation_contract_test`;
- `//src/test/llm/generation_config:gemma4_prompt_state_generation_contract_test`;
- `//src/test/llm/generation_config:openai_parallel_tool_calls_contract_test`;
- `//src/test/llm/gemma4_overlay:gemma4_chat_template_overlay_contract_test`;
- `//src/test/llm/gemma4_overlay:gemma4_google_jinja_contract_test`.

No `PASS` is inferred merely because these targets exist.

## Package contract

For the candidate root printed by the builder:

```powershell
$sha = git rev-parse HEAD
.\tests\windows\gemma4_standalone_package_test.ps1 `
  -CandidateRoot "C:\gemmamonster-artifacts\candidates\2026.4\<candidate>" `
  -ExpectedGitSha $sha `
  -ExpectedRuntimeProfile maintainer-rc2
```

This verifies the candidate envelope, exact dependency profile, hashes, required runtime DLLs, archive, provenance files and packaged `ovms.exe --version/--help` smoke.

## Exact known-good-runtime A/B build

If RC2 is unstable, or for the mandatory runtime-control experiment, build the identical source HEAD with the known-good RC1 dependency set. Again, use the fresh isolated root without expunge first:

```powershell
.\scripts\gemmamonster\build-stable-candidate.ps1 `
  -RuntimeProfile known-good-rc1 `
  -Label gemma4-stable-rc1-ab `
  -WithoutTests

.\scripts\gemmamonster\test-stable-source.ps1 `
  -RuntimeProfile known-good-rc1
```

The default dependency root is `C:\g54r1`, so RC1 and RC2 can coexist and be compared without replacing one another.

## Runtime acceptance, later gate

Source/build/package readiness is not runtime acceptance. Before declaring either candidate known-good, require:

1. loaded OpenVINO/GenAI/Tokenizers/TBB modules proven inside candidate package;
2. repeated same-tool calls with `parallel_tool_calls=true`, non-streaming;
3. the same repeated-call case under streaming with independent call IDs/indexes and unmixed arguments;
4. distinct parallel calls;
5. tool-result continuation;
6. multi-turn session continuity;
7. real OpenCode dogfood on Arc 140V;
8. RC1 versus RC2 A/B if behaviour or host stability differs.

The point of this line is not to manufacture another confidently named executable. It is to keep source provenance, dependency provenance and runtime evidence from impersonating one another.
