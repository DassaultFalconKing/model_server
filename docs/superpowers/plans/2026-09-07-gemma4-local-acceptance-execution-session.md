# Gemma4 Local Acceptance Integration Builder Session

Use this as the execution-session prompt for the agent that must assemble the Windows-testable ref.

```text
You are working directly in:

DassaultFalconKing/model_server

This is an IMPLEMENTATION / INTEGRATION BUILDER session, not a design session and not a Maintainer PR session.

PRIMARY GOAL
============
Produce exactly one pushed source ref on:

integration/gemma4-local-acceptance-2026.4

that combines the current accepted Gemma4 generation/API spine with the verified parser-hardening delta, passes every offline contract available in your environment, and is ready to be checked out and built on the target Windows Gemma4 machine.

Your final deliverable is one literal 40-character TEST_SHA plus the exact Windows acceptance invocation/runbook. Do not claim LOCAL_ACCEPTED in this session. LOCAL_ACCEPTED requires the separate Windows Task 8 run against the real Gemma4 endpoint.

AUTHORITIES, READ FIRST
=======================
Read these documents before any implementation action:

1. docs/superpowers/specs/2026-09-07-gemma4-local-acceptance-integration-gate-design.md
2. docs/superpowers/plans/2026-09-07-gemma4-local-acceptance-integration.md
3. docs/superpowers/plans/2026-09-07-gemma4-local-acceptance-windows-build-binding.md
4. docs/gemma4-auto-generator-port-handoff.md

The spec is authority. The implementation plan is the execution argument. The Windows binding overrides any vague build-command wording in the main plan.

SUPERPOWERS EXECUTION MODE
==========================
Use superpowers:using-git-worktrees before implementation.

If your environment provides subagents (Codex CLI/App, Claude Code, Gemini CLI, Copilot CLI or equivalent), use superpowers:subagent-driven-development and execute the plan continuously with per-task review.

If subagents are unavailable, use superpowers:executing-plans.

Do not invent a third ad hoc workflow.

SCOPE
=====
Execute Tasks 1 through 7 of:

docs/superpowers/plans/2026-09-07-gemma4-local-acceptance-integration.md

Do NOT execute Task 8 unless you are physically running on the intended Windows Gemma4 test machine with the actual model/runtime environment.

PRE-FLIGHT REF CONTRACT
=======================
Immediately re-resolve:

origin/fix/gemma4-responses-parallel-tool-policy
origin/fix/gemma4-parser-hardening-post-f36d2d75
upstream/main

Design-freeze values were:

SPINE   = 34c2f23d58e96a2c2ef1b3e2f940909c3131ace5
PARSER  = d1c21ac1a54d499e644e7619155944a3875fd071
BASE    = f36d2d758264ac5f371c344c49e485f582b07b5a
UPSTREAM= a114cfa8ed64e72337a83f55a018c1f8b0c65f0b
LIVE BASELINE = 81ff2f2cae8b79cc22f7103cf4c29eb1953f9789

Do not blindly require the remote branch heads to remain frozen. Re-resolve them first. If either source branch moved, compare the new head to the frozen head and determine whether the movement changes the plan's contracts. Record the ruling and actual SHAs before branch creation. Never silently substitute a moved ref.

PROTECTED REFS
==============
Do not move or rewrite:

- fork main
- upstream refs
- fix/gemma4-responses-parallel-tool-policy
- fix/gemma4-parser-hardening-post-f36d2d75
- fix/gemma4-google-template-session-state
- historical evidence refs
- tags
- releases

Do not merge your candidate into main.
Do not create a Maintainer PR.
Do not rewrite old live evidence.

INTEGRATION STRATEGY
====================
The candidate starts from the re-resolved integration spine.

Replay only the five parser-hardening commits unique to the parser source after the verified common base, in Git-reported order.

At design freeze those five commits were:

149c8e1b7d5c36dd3d62cb0c0fae1c217d6a7c4a
1598c3d68c652c35cab0af3c3c695f8b54365e43
18ad1514a97eafcd9be31cd9d9cfbaa09e1d4343
aa110ba01a78ed9583507024f7492f05021925a2
d1c21ac1a54d499e644e7619155944a3875fd071

Verify the actual list with git log before replay.

Do not merge fix/gemma4-opencode-auto-tool-native. Compare it only for behavior that is missing from the current TriggeredTags-based auto implementation. A missing behavior must first become a RED contract test before any port.

TEST AUTHORITY
==============
At minimum the final candidate must freshly pass:

bazel test //src/test/llm/gemma4_fast:gemma4_parser_contract_test
bazel test //src/test/llm/generation_config:gemma4_generation_contract_test
bazel test //src/test/llm/generation_config:openai_parallel_tool_calls_contract_test

and from ab-evidence:

python -m unittest \
  test_reliability_grounded_harness_v2.py \
  test_local_acceptance_gate.py \
  test_live_chain_harness.py

Do not report an unexecuted target as PASS.

FEATURE CONTRACTS THAT MUST SURVIVE
===================================
Parser:
- recursive native arguments
- lexically lossless valid JSON numbers
- malformed numeric-looking scalars never emit invalid JSON
- bounded bare call recovery
- incomplete call-like prose remains prose
- Windows path fidelity
- request-scoped allowed tool registry
- malformed/unavailable calls fail closed
- streaming state preserves incomplete calls without premature execution

Generation:
- tool_choice=none prohibits tool grammar
- auto uses lazy-capable TriggeredTags with <|tool_call> trigger and at_least_one=false
- required is mandatory and cannot silently fall back unconstrained
- named permits only the named tool and is mandatory
- no empty ConstString("")
- nested request JSON Schema survives unchanged
- parallel_tool_calls controls stop_after_first

API/session:
- Chat Completions policy preserved
- Responses tool policy preserved
- parallel_tool_calls not silently reset
- chained session binds tool result and continuation to exact candidate SHA
- old 81ff2f2c PASS is regression reference only, never replacement evidence

ACCEPTANCE TOOLING
==================
Implement the plan's fail-closed local_acceptance_gate.py and tests.

Every required case must resolve to literal PASS for LOCAL_ACCEPTED.
These are all failures for promotion:

FAIL
ERROR
NOT_RUN
BLOCKED_BY_PLATFORM
missing evidence
wrong source SHA
missing/wrong binary SHA256

Prepare the Windows runner and runbook exactly as the plan and Windows binding specify.

WINDOWS BUILD BINDING
=====================
The real local acceptance build will run from repo root with:

$env:PYTHONHOME="C:\opt\Python312"

Do NOT source:

C:\llm\ovms\setupvars.ps1

Development build, only for iteration:

.\windows_build_fast.ps1 -Mode Dev -WithPython $true -SkipFastTests -OpenVinoDir "C:/opt/openvino/runtime/cmake"

Final G1 verification build:

.\windows_build_fast.ps1 -Mode Verify -WithPython $true -OpenVinoDir "C:/opt/openvino/runtime/cmake"

Expected built executable:

.\bazel-bin\src\ovms.exe

The Windows runner must hash the executable it just built. An already installed C:\llm\ovms\ovms.exe is not acceptable as the candidate binary.

COMMIT DISCIPLINE
=================
Keep logical changes separately reviewable.

Required sequence is approximately:

1. pin actual integration inputs
2. replay parser commits with their original logical boundaries
3. generation/API gap fix only if a RED contract proves one exists
4. fail-closed local acceptance gate
5. chained-session evidence normalization
6. exact-SHA Windows runner/runbook

Do not squash the entire integration history into one giant commit.

FINAL OFFLINE GATE
==================
Before push:

- run all listed C++ tests fresh
- run all listed Python tests fresh
- verify git status is clean
- verify candidate descends from recorded integration spine
- verify 81ff2f2c remains an ancestor
- record TEST_SHA=$(git rev-parse HEAD)

Push only:

integration/gemma4-local-acceptance-2026.4

The pushed branch head must equal TEST_SHA.

Do not add a self-referential manifest commit after computing TEST_SHA.
The runtime acceptance run records TEST_SHA after checkout.

FINAL REPORT FORMAT
===================
Return exactly these fields, followed by concise notes for any non-PASS item:

INTEGRATION_BRANCH:
integration/gemma4-local-acceptance-2026.4

SPINE_SHA:
<literal resolved SHA>

PARSER_SOURCE_SHA:
<literal resolved SHA>

COMMON_BASE_SHA:
<literal resolved SHA>

UPSTREAM_REFERENCE_SHA:
<literal resolved SHA>

TEST_SHA:
<literal pushed candidate SHA>

PARSER_TEST:
PASS | FAIL

GENERATION_TEST:
PASS | FAIL

OPENAI_POLICY_TEST:
PASS | FAIL

HARNESS_UNIT_TESTS:
PASS | FAIL

WINDOWS_RUNNER_READY:
YES | NO

LOCAL_WINDOWS_ACCEPTANCE:
NOT_RUN

MAINTAINER_PR_SOURCE:
NO

The only successful terminal state for this session is a pushed TEST_SHA with all offline gates PASS and LOCAL_WINDOWS_ACCEPTANCE explicitly NOT_RUN. The next step is the real Windows Task 8 run. Only its full LOCAL_ACCEPTED result can change MAINTAINER_PR_SOURCE to YES.
```
