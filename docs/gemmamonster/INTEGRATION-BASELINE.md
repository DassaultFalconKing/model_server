# GEMMAMONSTER integration baseline

Date: 2026-09-07
Status: LEADING INTEGRATION POLICY

## Goal

Build a new fork `main` from fresh OVMS upstream plus the minimal current Gemma4 parser/generator/tool-calling patchset, without wholesale-merging historical feature branches, raw evidence trees, fork-only fast-build divergence or obsolete experiments.

## Reconciled investigation authority

The clean-port investigation performed by Muse is external evidence authority for the exact lineage analysis:

```text
repo:   DassaultFalconKing/OpenVino-For-Gemma-4
branch: fix/gemma4-candidate-local-acceptance
commit: f62350dbb58222afdf47b9232c72fcbaf25642d0
file:   docs/gemmamonster-leading-docs/2026-09-07-gemma4-clean-port-investigation.md
```

That report re-resolved all source refs, identified the minimal production/test files, reconstructed parser/generator dependency pairs, classified upstream overlap and produced an 11-step clean integration plan. This document incorporates its accepted findings; the report remains provenance/evidence rather than a second copy of the leading contract.

## Resolved topology

At the investigation point:

```text
upstream main:
5fe145e54064d7a048fd7cdc9603f4bde6f0f175

fork main:
be410567f2b3f8146eda87087beb59b67199c893

parser hardening:
fix/gemma4-parser-hardening-post-f36d2d75
d1c21ac1a54d499e644e7619155944a3875fd071

generator feature:
feature/gemma4-llamacpp-auto-generator-port
6db0c8fb797a15f5acfd0c4d23b4ef1a75eae196

responses policy fix:
fix/gemma4-responses-parallel-tool-policy
34c2f23d58e96a2c2ef1b3e2f940909c3131ace5

local merge-test:
integration/gemma4-hardening-on-ovms-2026.4
c1604e2246bf56908837d6f2c4220cc44e1a2021
```

Every implementation/acceptance session must re-resolve refs before acting.

## Recommended source base

The clean tool-calling candidate must branch from the exact fresh upstream tip:

```text
5fe145e54064d7a048fd7cdc9603f4bde6f0f175
```

The local merge-test equivalent after upstream synchronization is:

```text
0f1be4c76744364fa2301e993de3095ab249020c
```

Do **not** use `be410567...` as the semantic clean-port base. The investigation found `upstream..be410567` spans 142 files and includes fork-only fast-build deletions/divergence unrelated to the Gemma4 tool-calling port. Those changes must not leak into the clean candidate merely because they happen to exist on the current fork main.

The final fork-main promotion strategy may still synchronize the fork through PR #9 or an equivalent explicit operation, but the clean Gemma4 patchset itself is defined relative to the exact upstream source base above.

## PR interpretation

### PR #9 — upstream synchronization

Useful synchronization surface. The upstream head was re-resolved at `5fe145e5...` and had not drifted at investigation time. It is not a license to inherit unrelated fork-main divergence into the clean Gemma patchset.

### PR #10 — parser hardening historical surface

Do not merge wholesale. Its branch contains the required parser semantics but also dozens of commits, hundreds of files, evidence and session/template history. Use the exact commits/symbols below as port coordinates.

### PR #11 — Responses policy serialization

Mandatory narrow semantic fix:

```cpp
writer.Bool(true);
```

to:

```cpp
writer.Bool(request.parallelToolCalls);
```

Source coordinate:

```text
34c2f23d58e96a2c2ef1b3e2f940909c3131ace5
```

### Older PRs / feature lanes

Provenance only unless an exact semantic delta below references them. Do not revive them as final integration surfaces.

## Minimal parser port

The parser is a **manual semantic port**, not a branch merge or whole-file overwrite.

Required source coordinates:

```text
798e99e04d53fba2d  boundary ownership / parser routing / empty-tools guard
6f6272e11ff10453   recoverable bare-call foundation
30d2b5866a290faa   lossless numeric/native JSON path + bounded buffering
149c8e1b7d5c36dd   strict JSON number lexeme gate
1598c3d68c652c35   bare-call line/prefix hold fix
 aa110ba01a78ed95  currentCallStart fail-closed EOF flush/reset state
```

Required coupling rules:

```text
30d2b586 must not be ported without 149c8e1b
6f6272e1 must not be ported without 1598c3d6
```

Primary production files:

```text
src/llm/io_processing/gemma4/gemma4_tool_parser.cpp
src/llm/io_processing/gemma4/gemma4_tool_parser.hpp
src/llm/io_processing/output_parser.cpp
src/llm/io_processing/output_parsing_config.hpp
src/llm/apis/openai_api_handler.cpp   # empty-tools guard only
```

The generator branch contains a stale parser snapshot and must not overwrite the later hardening fixes.

## Minimal generator/API port

Core generator/API source coordinates:

```text
80b885281443d7b0   ToolConstraintMode + TriggeredTags AUTO + mandatory Hard grammar
158c6c8aa2447c79   base model-specific validation fallback hook
ac5a8deead2e77f64   Gemma hard-choice fallback + parallel stop_after_first wiring
2badb13ec7c954f9   OpenAIRequest.parallelToolCalls{true}
1244577fb30474a9c   parallel policy parsing / virtual parseTools
b705fc19dff874da3   Chat Completions endpoint override
0cd155a88afbd11fe   Responses endpoint override
34c2f23d58e96a2c   Responses serialization one-line fix
```

`generation_config_builder.hpp` requires a manual stacked port of `80b88528 + ac5a8dee`. The small API/header commits may be applied cleanly only after re-checking against the fresh upstream tree.

Explicitly rejected:

```text
c1698126b489acee  accidental wholesale openai_responses.cpp rewrite
6db0c8fb797a15f5a as a port unit; it is the restore/head coordinate, not the narrow Responses patch
35c5262d9b270005d  docs-only handoff commit as a merge/cherry-pick unit
e51cbe8461d240031  docs/plan only
```

## Minimal production file set

Current expected tool-calling production surface is 12 files:

```text
src/llm/io_processing/gemma4/gemma4_tool_parser.cpp
src/llm/io_processing/gemma4/gemma4_tool_parser.hpp
src/llm/io_processing/output_parser.cpp
src/llm/io_processing/output_parsing_config.hpp
src/llm/apis/openai_api_handler.cpp
src/llm/apis/openai_api_handler.hpp
src/llm/apis/openai_request.hpp
src/llm/apis/openai_completions.hpp
src/llm/apis/openai_responses.hpp
src/llm/apis/openai_responses.cpp
src/llm/io_processing/base_generation_config_builder.hpp
src/llm/io_processing/generation_config_builder.hpp
```

This is an expected surface, not permission to replace whole files. Port only the identified semantic hunks.

## Required test surface

Keep/add the focused contracts associated with the production port, including:

```text
src/test/llm/gemma4_fast/BUILD
src/test/llm/gemma4_fast/gemma4_parser_contract_test.cpp
src/test/llm/gemma4_fast/gemma4_parser_hardening_test.cpp
src/test/llm/generation_config/BUILD
src/test/llm/generation_config/gemma4_generation_contract_test.cpp
src/test/llm/generation_config/openai_parallel_tool_calls_contract_test.cpp
src/test/llm/output_parsers/gemma4_v2_contract_test.cpp
src/test/kfs_rest_test.cpp                       # only accepted generic-header hunk
src/test/llm/max_model_length_test.cpp           # retain env/session-id semantics, no false store header
src/test/multi_part_parser_drogon_test.cpp       # rewrite false store header fixture
```

Generator lineage deletion of `gemma4_parser_hardening_test.cpp` is not accepted; the clean candidate keeps that regression coverage.

## Session-store finding

Status: **REWRITE**.

`X-OVMS-Session-Store` is not a supported per-request store-path contract in the inspected production source. `c1604e22` already corrected `kfs_rest_test.cpp` to a neutral `X-OVMS-Test-Passthrough` fixture and removed the false request header from `max_model_length_test.cpp` while retaining `OVMS_SESSION_STORE_DIR` and session-id behavior.

Remaining assertions in `src/test/multi_part_parser_drogon_test.cpp` must be rewritten to the same neutral generic-header fixture. This is test-contract cleanup, not a new session feature.

## Upstream overlap rules

The current upstream Qwen3Coder quoted-name fix (`5fe145e5`, #4502) has zero semantic/file overlap with the Gemma4 parser work and must be preserved.

Known textual overlap requiring manual resolution while keeping upstream first:

```text
src/BUILD
src/llm/io_processing/chat_template/analyzer.cpp
src/llm/io_processing/chat_template/caps.hpp
src/llm/io_processing/input_processors/chat_template_adapter.cpp
src/llm/io_processing/input_processors/chat_template_adapter.hpp
src/test/kfs_rest_test.cpp
src/test/llm/chat_template_adapter_test.cpp
src/test/llm/chat_template_analyzer_test.cpp
```

Also preserve upstream `qwen3coder`/`utils` tests and `probe.cpp/.hpp`; fork deletions must not be carried by accident.

## Session/template scope boundary

The clean tool-calling PR does **not automatically include** the historical session/template production stack:

```text
src/llm/servable.cpp/.hpp
chat_template analyzer/caps/adapter session hunks
py_jinja_template_processor.cpp
gemma4_reasoning_parser.cpp session/template hunks
windows_build_fast.ps1
scripts/gemma4/*
```

Those changes require a separate explicit design decision / PR. This is the remaining design-scope blocker recorded by the Muse investigation. Do not silently fold them into the parser/generator port.

## Excluded historical material

Do not place the following in the clean code PR by default:

```text
ab-evidence/**
raw response/runtime dumps
*.raw
*.pyd
*sha256*
*version.txt
*pid.txt
build-output*/launch-env*
HANDOFF.md
historical docs/handoffs/plans as production delta
old acceptance claims not reproduced on the final exact head
fork-only fast-build divergence unrelated to this port
```

Harnesses/docs may be carried by a separate evidence/documentation PR when useful.

## Recommended implementation sequence

1. branch from exact `5fe145e5...` after re-resolution;
2. manually port parser boundary ownership (`798e99e0`);
3. manually port numeric/bare-call hardening (`6f6272e1 + 30d2b586 + 149c8e1b + 1598c3d6 + aa110ba0`);
4. port Gemma-specific validation fallback (`158c6c8a + ac5a8dee part 1`);
5. port `parallel_tool_calls` request/API plumbing (`2badb13e + 1244577f + b705fc19 + 0cd155a8`);
6. port TriggeredTags/TagsWithSeparator generator behavior (`80b88528 + ac5a8dee part 2`);
7. apply only the narrow Responses serialization fix (`34c2f23d`);
8. port exact focused parser/generator/OpenAI tests and session-store test cleanup;
9. resolve upstream overlap keeping upstream changes plus only required Gemma hunks;
10. run Windows build/focused C++ verification;
11. run live Arc 140V acceptance.

If any manual port requires semantics beyond the named symbols/contracts, stop and record a design conflict rather than improvising.

## No-wholesale-merge rule

Not acceptable as final solution:

```text
git merge fix/gemma4-parser-hardening-post-f36d2d75
git merge feature/gemma4-llamacpp-auto-generator-port
git merge 35c5262d9b270005da18a505c06bf3a412394f3b
```

Throwaway merge tests may be used as evidence only.

## Current status

The clean-port lineage investigation is complete and reports:

```text
OVERALL: NEEDS_DESIGN_DECISION
```

The remaining source-scope decision is whether the separate session/template stack belongs in this tool-calling PR. Leading policy currently treats it as **deferred/separate unless explicitly approved**.

The Windows/Bazel acceptance-environment investigation remains independent and must establish runnable focused C++ tests/build prerequisites.

## Promotion rule

A clean PR being small/mergeable is necessary but insufficient. The exact candidate must satisfy [`ACCEPTANCE-MATRIX-V1.md`](ACCEPTANCE-MATRIX-V1.md) before promotion to fork `main`.
