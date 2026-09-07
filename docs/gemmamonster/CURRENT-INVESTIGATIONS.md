# GEMMAMONSTER current investigations

Date: 2026-09-07
Status: ACTIVE OPERATING DOCUMENT

## Purpose

This file records the currently authorized investigation lanes that can proceed in parallel without multiple agents editing the same parser/generator code and manufacturing conflicts for sport.

## Lane 1 — clean integration lineage investigation

Goal:

Determine the minimal production + regression-test patchset required to reconstruct the current Gemma4 parser/generator/tool-calling semantics on top of fresh upstream-derived fork `main`.

The investigation must work at commit/file/symbol/semantic-change level, not propose wholesale merges of historical feature branches.

Primary source coordinates:

```text
upstream main:
5fe145e54064d7a048fd7cdc9603f4bde6f0f175

fork main at investigation start:
be410567f2b3f8146eda87087beb59b67199c893

parser hardening:
fix/gemma4-parser-hardening-post-f36d2d75
d1c21ac1a54d499e644e7619155944a3875fd071

generator feature:
feature/gemma4-llamacpp-auto-generator-port
6db0c8fb797a15f5acfd0c4d23b4ef1a75eae196

Responses policy fix:
fix/gemma4-responses-parallel-tool-policy
34c2f23d58e96a2c2ef1b3e2f940909c3131ace5
```

Required output:

- minimal parser production port;
- minimal generator/API production port;
- exact regression tests to retain;
- upstream overlap/conflicts;
- session-store cleanup finding;
- clean prototype diffstat if safe to construct;
- recommended commit structure for the final integration PR;
- explicit files/directories to exclude from the clean port.

Forbidden as final solution:

```text
git merge fix/gemma4-parser-hardening-post-f36d2d75
git merge feature/gemma4-llamacpp-auto-generator-port
git merge 35c5262d9b270005da18a505c06bf3a412394f3b
```

## Lane 2 — Windows/Bazel acceptance environment investigation

Goal:

Make the focused Windows C++ acceptance lane reproducible without modifying Gemma production code.

Investigate:

- Bazel executable/version;
- MSYS bash vs WSL bash ambiguity;
- MSVC/BAZEL_VS/BAZEL_VC/toolset;
- Python/PYTHONHOME/PYTHON_BIN_PATH behavior;
- OpenVINO/OpenCV environment;
- Bazel cache/server analysis stalls;
- minimum Gemma4 tokenizer fixture needed by parser contract tests;
- Bazel sandbox `STATUS_DLL_NOT_FOUND` cases;
- fragility in `windows_build_fast.ps1` preflight logic.

Required result states remain:

```text
PASS
FAIL
BLOCKED
NOT_RUN
```

The absence of the full 26B model must not be used to classify tokenizer-only unit tests as universally blocked.

## Lane 3 — Acceptance Matrix v1 ownership

The canonical promotion gate is:

[`ACCEPTANCE-MATRIX-V1.md`](ACCEPTANCE-MATRIX-V1.md)

The matrix may be refined when an investigation demonstrates that a case is impossible, redundant, incorrectly scoped or missing a real regression class. Changes to the matrix are leading-contract changes and must explain the evidence that caused them.

## Lane 4 — differential parser corpus

Not yet assigned.

Planned scope:

- canonical native call forms;
- recursive values;
- numeric-looking scalars;
- Windows paths/backslashes;
- incomplete/bare calls;
- multiple calls;
- reasoning → tool transition;
- malformed/truncated calls;
- unary vs streaming split permutations.

The corpus should compare deterministic invariants, not blindly force parity with peer runtimes.

## Lane 5 — runtime/performance harness

Not yet assigned.

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

No grammar cache work is authorized until measured compiler/initialization overhead is materially visible in request latency or throughput.

## Lane 6 — live Arc 140V acceptance

Blocked until a clean integration candidate and usable Windows build exist.

Required live ingredients:

- exact candidate SHA;
- exact built `ovms.exe` + SHA256;
- Intel Arc 140V target;
- Gemma4 Wondernuttz/Heretic 26B lane or explicitly superseding model;
- pinned Google canonical template;
- raw requests/responses;
- server logs;
- tool-choice + streaming + chained-loop matrix.

## Lane 7 — OpenCode/NovaClaw dogfood

Blocked until basic live OVMS matrix is credible.

OpenCode must exercise real request shapes, including complex `question` schemas.

NovaClaw must exercise fragmented streaming and chained tool-result behavior. A client-side failure must be separated from raw OVMS protocol behavior before being attributed to parser/generator code.

## Lane ownership rule

An investigator may read any lane's evidence but must not edit another lane's production code unless the coordinator explicitly reassigns scope.

If an investigation discovers a production bug outside its scope, report:

```text
BOUNDARY
ROOT_CAUSE
EVIDENCE
RECOMMENDED_OWNER
MINIMAL_REPRODUCER
```

and stop short of speculative cross-lane fixes.
