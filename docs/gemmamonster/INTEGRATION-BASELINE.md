# GEMMAMONSTER integration baseline

Date: 2026-09-07
Status: LEADING INTEGRATION POLICY

## Goal

Build a new fork `main` from fresh OVMS upstream plus the minimal current Gemma4 parser/generator/tool-calling patchset, without wholesale-merging historical feature branches, raw evidence trees or obsolete experiments.

## Resolved topology at document creation

```text
fork main:
be410567f2b3f8146eda87087beb59b67199c893

upstream main:
5fe145e54064d7a048fd7cdc9603f4bde6f0f175

parser hardening branch:
fix/gemma4-parser-hardening-post-f36d2d75
d1c21ac1a54d499e644e7619155944a3875fd071

generator feature branch:
feature/gemma4-llamacpp-auto-generator-port
6db0c8fb797a15f5acfd0c4d23b4ef1a75eae196

responses policy fix:
fix/gemma4-responses-parallel-tool-policy
34c2f23d58e96a2c2ef1b3e2f940909c3131ace5
```

These values are coordinates, not eternal truth. Every implementation or acceptance session must re-resolve refs before acting.

## Relevant PRs

### PR #9 — upstream sync

Purpose: update fork `main` to current OVMS upstream.

Observed base/head:

```text
base: fork main @ be410567...
head: openvinotoolkit/model_server:main @ 5fe145e5...
```

Policy: this is the preferred first layer for the new fork-main line, subject to exact-head re-resolution before merge.

### PR #10 — parser hardening historical integration surface

The PR description is narrow, but its actual lineage is not: it carries dozens of commits and hundreds of files, including historical evidence and prior Gemma work.

Policy: **do not use PR #10 as the final clean integration surface**. Use its production changes, tests and commit history as source material for a minimal port.

### PR #11 — Responses `parallel_tool_calls` serialization

Observed change:

```cpp
writer.Bool(true);
```

to:

```cpp
writer.Bool(request.parallelToolCalls);
```

Scope review found one file, one semantic hunk, `+1/-1`, no parser/generator changes.

Policy: this fix is part of the intended clean generator/API stack.

### Older PRs #4/#5/#6 and predecessor lanes

Policy: provenance and regression evidence only unless a clean-port investigation identifies a still-required semantic change. Do not revive them wholesale as the new main integration mechanism.

## Merge-test evidence

A local merge-test branch was reported as:

```text
integration/gemma4-hardening-on-ovms-2026.4
c1604e2246bf56908837d6f2c4220cc44e1a2021
```

Created merge commits:

```text
0f1be4c76744364fa2301e993de3095ab249020c
    merge: sync fork main with upstream OVMS 2026.4 main

d886ca3416576c4546d2b59b660547f23de0d6b5
    merge: integrate Gemma4 parser hardening

c1604e2246bf56908837d6f2c4220cc44e1a2021
    test(v3): remove false session-store request header contract
```

The attempt to merge generator handoff commit `35c5262d9b270005da18a505c06bf3a412394f3b` was correctly blocked because that commit is embedded in a large feature history and is not a self-contained generator patch.

This merge-test proves mechanical compatibility evidence, not final clean-main suitability.

## Clean integration policy

The final candidate must be constructed conceptually as:

```text
fresh upstream-synced fork main
        +
minimal current parser production delta
        +
minimal current generator production delta
        +
OpenAI parallel_tool_calls plumbing
        +
Responses serialization fix
        +
focused regression tests
        +
minimal required docs/harness
```

Explicitly excluded by default:

```text
raw ab-evidence campaign dumps
old binary/runtime artifacts
historical merge commits whose semantics are already represented cleanly
obsolete experiments
old acceptance claims not reproduced on the final exact head
```

## No-wholesale-merge rule

The following are not acceptable as the final solution:

```text
git merge fix/gemma4-parser-hardening-post-f36d2d75
git merge feature/gemma4-llamacpp-auto-generator-port
git merge 35c5262d9b270005da18a505c06bf3a412394f3b
```

They may be used in throwaway investigation branches to understand conflicts, but the final reviewable PR must expose a small semantic delta against its fresh upstream-derived base.

## Current active investigations

Two independent lanes are authorized:

1. clean integration lineage investigation: determine the minimal parser/generator files, symbols and commits to port;
2. Windows/Bazel acceptance-environment investigation: remove ambiguity around Bazel, Python, MSYS, MSVC, tokenizer fixture and focused C++ test execution without modifying Gemma production code.

See [`CURRENT-INVESTIGATIONS.md`](CURRENT-INVESTIGATIONS.md).

## Promotion rule

A clean PR being mergeable is necessary but insufficient. The exact resulting candidate must satisfy [`ACCEPTANCE-MATRIX-V1.md`](ACCEPTANCE-MATRIX-V1.md) before promotion to fork `main`.
