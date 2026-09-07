# GEMMAMONSTER current investigations

Date: 2026-09-07
Status: ACTIVE OPERATING DOCUMENT

## Purpose

This file records investigation lanes that can proceed in parallel without multiple agents editing the same parser/generator code.

## Lane 1 — clean integration lineage investigation

Status: **COMPLETE — NEEDS_DESIGN_DECISION**.

Evidence authority:

```text
repo:   DassaultFalconKing/OpenVino-For-Gemma-4
branch: fix/gemma4-candidate-local-acceptance
commit: f62350dbb58222afdf47b9232c72fcbaf25642d0
file:   docs/gemmamonster-leading-docs/2026-09-07-gemma4-clean-port-investigation.md
```

The investigation re-resolved upstream/fork/parser/generator/Responses refs and established:

- exact clean source base: upstream `5fe145e54064d7a048fd7cdc9603f4bde6f0f175`;
- 12-file expected production tool-calling surface;
- exact parser commit/symbol set and coupling rules;
- exact generator/API/parallel-tool-call source coordinates;
- mandatory Responses one-line fix `34c2f23d...`;
- session-store test contract status `REWRITE`;
- known 8-file upstream textual overlap;
- session/template production stack deferred from the clean tool-calling PR unless separately approved;
- no wholesale merges of parser/generator historical branches.

Canonical integration result is incorporated into [`INTEGRATION-BASELINE.md`](INTEGRATION-BASELINE.md).

Remaining design decision before implementation: confirm that the session/template stack remains a separate PR. Until explicitly changed, leading policy is **defer/separate**.

## Lane 2 — Windows/Bazel acceptance environment investigation

Status: **ACTIVE**.

Goal: make focused Windows C++ acceptance reproducible without modifying Gemma production code.

Investigate:

- Bazel executable/version;
- MSYS bash vs WSL bash ambiguity;
- MSVC/BAZEL_VS/BAZEL_VC/toolset;
- Python/PYTHONHOME/PYTHON_BIN_PATH behavior;
- OpenVINO/OpenCV environment;
- Bazel cache/server analysis stalls;
- minimum Gemma4 tokenizer fixture needed by parser/generator contracts;
- Bazel sandbox `STATUS_DLL_NOT_FOUND` cases;
- fragility in `windows_build_fast.ps1` preflight logic.

Required result vocabulary remains `PASS / FAIL / BLOCKED / NOT_RUN`.

The absence of the full 26B model must not classify tokenizer-only unit tests as universally blocked.

## Lane 3 — Acceptance Matrix v1 ownership

Status: **ACTIVE CANONICAL GATE**.

[`ACCEPTANCE-MATRIX-V1.md`](ACCEPTANCE-MATRIX-V1.md) is the promotion contract. Muse evidence adds concrete final-candidate checks that must be represented in that gate: `Gemma4OutputParserTest.*`, `smoke_tool_call.py --mode all`, the full 17-case runtime probe, streaming `delta.tool_calls`/`finish_reason=tool_calls` without markup leakage, and a TRACE proving the hard required/named lane starts at the Gemma tool-call token boundary.

## Lane 4 — differential parser corpus

Status: **NOT ASSIGNED**.

Planned scope:

- canonical native calls;
- recursive values;
- numeric-looking scalars;
- Windows paths/backslashes;
- incomplete/bare calls;
- multiple calls;
- reasoning → tool transition;
- malformed/truncated calls;
- unary vs streaming split permutations.

The corpus compares deterministic invariants, not blind parity with peer runtimes.

## Lane 5 — runtime/performance harness

Status: **NOT ASSIGNED**.

Planned measurements on the exact built candidate:

```text
no-tools TTFT
auto/no-call TTFT
auto/call TTFT
required TTFT
named TTFT
parallel=true/false TTFT
decode tok/s
wall tok/s
structured-output/xgrammar initialization/compile cost when observable
```

No grammar cache work is authorized until measured compiler/initialization overhead is materially visible.

## Lane 6 — live Arc 140V acceptance

Status: **BLOCKED ON CLEAN CANDIDATE + WINDOWS BUILD**.

Required live ingredients:

- exact candidate SHA and upstream base;
- exact built/deployed `ovms.exe`, version and SHA256;
- Intel Arc 140V;
- Gemma4 Wondernuttz/Heretic 26B lane or recorded superseding model;
- pinned Google canonical template;
- `vlm-stable`, JINJA, REST 8000 launch provenance;
- `smoke_tool_call.py --mode all`;
- full 17-case probe;
- required/named first-token TRACE;
- raw requests/responses/server logs;
- tool-choice, streaming and chained-loop matrix.

## Lane 7 — OpenCode/NovaClaw dogfood

Status: **BLOCKED ON BASIC LIVE OVMS MATRIX**.

OpenCode must exercise real request shapes including complex `question` schemas.

NovaClaw must exercise later-turn and fragmented streaming/tool-result behavior. Client failure must be separated from raw OVMS behavior before attribution to parser/generator code.

## Lane ownership rule

An investigator may read any lane's evidence but must not edit another lane's production code unless scope is explicitly reassigned.

If an investigation discovers an out-of-scope production bug, report:

```text
BOUNDARY
ROOT_CAUSE
EVIDENCE
RECOMMENDED_OWNER
MINIMAL_REPRODUCER
```

and stop short of speculative cross-lane fixes.
