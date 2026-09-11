# GPU runtime fault containment — local Windows build and test handoff

Status: **LOCAL AGENT EXECUTION RUNBOOK**

Target branch: `fix/gemma4-gpu-fault-containment-sketch`

Hot-line parent at branch creation: `local/build-gemmamonster-2026.4-dc668c1 @ 4e2e71a0b1dbfae453f75ae069ef424248c9740a`.

Frozen semantics: `docs/gemmamonster/GPU-RUNTIME-FAULT-CONTAINMENT-CONTRACT.md`.

This branch contains a **sketch**, not a production-accepted recovery implementation. Your job is to build it on the Windows Intel Arc host, prove or falsify the frozen contracts, and return exact evidence. Do not broaden the implementation while testing it.

## 0. Mandatory bootstrap

Before the first build/test command, read completely:

1. `AGENTS.md`
2. `docs/gemmamonster/AGENT-AUTHORITY-INDEX.md`
3. `docs/gemmamonster/AGENT-NEGATIVE-CONTRACT.md`
4. `docs/gemmamonster/GPU-RUNTIME-FAULT-CONTAINMENT-CONTRACT.md`
5. this file

Resolve and record the actual Git state:

```powershell
git fetch --all --prune
git switch fix/gemma4-gpu-fault-containment-sketch
git pull --ff-only
git rev-parse HEAD
git rev-parse HEAD^{tree}
git status --porcelain=v1
git merge-base HEAD local/build-gemmamonster-2026.4-dc668c1
```

Expected relationship: the branch must descend from hot-line parent `4e2e71a0b1dbfae453f75ae069ef424248c9740a`. The branch HEAD may be newer than the SHA recorded in this document. The branch name is not authority; record the resolved SHA.

**STOP if the tree is dirty before the build unless the dirt is a known Bazel convenience link explicitly tolerated by the existing builder.**

## 1. What this sketch is supposed to prove

Two independent properties:

### A. Gemma4 model-local circuit breaker

For `tool_parser=gemma4`, an ambiguous oneDNN primitive execution failure is conservative enough to quarantine that executor/model instance. It must not be stepped again.

### B. Generic server-side fatal GPU containment

An explicit context-fatal GPU signal such as `CL_OUT_OF_RESOURCES`, `clFinish` failure or device loss must quarantine the affected continuous-batching executor without terminating the entire OVMS process.

Do not merge these with root-cause remediation. In particular, **do not change OpenVINO/GenAI pins while evaluating the containment build**.

## 2. TDD provenance

The deliberate RED checkpoint is:

```text
19446c33123c1c707d0dcc5d61ed2e5dd50c98e2
```

At that checkpoint the new Bazel target was wired while its implementation header did not yet exist. It is expected to fail compilation. This RED replay is optional because it requires temporarily detaching the worktree; it exists to establish test-first provenance, not to waste Arc-host time proving that a missing file is still missing.

The GREEN target on the current branch is:

```text
//src/test/llm/gemma4_fast:gemma4_runtime_fault_contract_test
```

The established parser regression target remains:

```text
//src/test/llm/gemma4_fast:gemma4_parser_contract_test
```

The canonical source-contract runner on this branch now includes the new runtime-fault target.

## 3. Runtime profiles: do not improvise

Use the existing profile authority in `scripts/gemmamonster/stable-runtime-profiles.ps1`.

### RC2 containment build

```text
RuntimeProfile: maintainer-rc2
OpenVINO:       227c33757d1ef95d4da506d00686f923fdd2a535
GenAI:          7ea2546852a382cd16bd22dea0cfad2db70ed744
Tokenizers:     a04accf6282d9b304214b492694b18c3979f667a
Default root:   C:\g54r2
```

### RC1 differential oracle

```text
RuntimeProfile: known-good-rc1
OpenVINO:       61afcb26271140347709138b13d678e8b1b5925c
GenAI:          5f7f1278107d7eae3990ce906bbcfcb69ac3397f
Tokenizers:     a04accf6282d9b304214b492694b18c3979f667a
Default root:   C:\g54r1
```

The first containment build is RC2. RC1 is a later **same-source differential experiment**, not a fallback silently substituted into the build.

## 4. Source contract gate

If the RC2 dependency root is already provisioned, run:

```powershell
pwsh -NoProfile -File .\scripts\gemmamonster\test-stable-source.ps1 `
  -RuntimeProfile maintainer-rc2 `
  -Gemma4TokenizerPath "<PATH-TO-A-GEMMA4-MODEL-WITH-TOKENIZER>"
```

If `GEMMA4_TOKENIZER_PATH` is already correctly established for the known-good model, the explicit parameter may be omitted only after recording the resolved path in the report.

Required result:

```text
GEMMAMONSTER_SOURCE_CONTRACTS_PASS
runtime_profile: maintainer-rc2
workspace_restored_byte_exact: true
```

The runner must execute the new target `gemma4_runtime_fault_contract_test` together with the existing Gemma4 parser/generation/overlay contracts.

If this gate fails, **do not proceed to live fault testing**. Preserve the full log under `tmp\gemmamonster-contracts` and report the first failing target/compile error.

## 5. Build the exact RC2 sketch candidate

Use the proven candidate builder, not a hand-written dependency mix:

```powershell
pwsh -NoProfile -File .\scripts\gemmamonster\build-stable-candidate.ps1 `
  -RuntimeProfile maintainer-rc2 `
  -Label gpu-fault-containment-sketch
```

The builder intentionally:

- binds the exact runtime profile;
- transiently rewrites the Windows `WORKSPACE` dep-root pins and restores them byte-exact;
- invokes the repository `windows_build.bat`;
- builds with Python and tests unless switches explicitly disable them;
- records source SHA/tree and packaged DLL provenance;
- refuses a dirty tree by default.

Do **not** pass `-AllowDirty`, `-WithoutTests`, `-NoPython`, or change pins for the first acceptance attempt.

The underlying Windows builder uses the repository-supported Bazel path and `--config=win_mp_on_py_on`; do not replace it merely because a different Bazel incantation looks shorter. Humans have already paid for that lesson.

Record from the produced candidate:

```text
source SHA
source tree SHA
runtime profile
OpenVINO SHA/version
GenAI SHA/version
Tokenizers SHA/version
ovms.exe SHA256
candidate directory
build log
package/provenance manifest paths
```

## 6. Static regression gates after build

Re-run the source contracts against the built profile if the candidate builder did not already leave equivalent evidence. At minimum the report must include outcomes for:

```text
//src/test/llm/gemma4_fast:gemma4_runtime_fault_contract_test
//src/test/llm/gemma4_fast:gemma4_parser_contract_test
```

Also retain the full existing stable-source contract result. Do not call the sketch GREEN merely because the new tiny classifier test passes while the parser/generation suite burns behind it.

## 7. Baseline live sanity before fault work

Launch the candidate using the same Gemma4 26B model/config used by the known-running RC2 candidate. Preserve:

- `tool_parser=gemma4`;
- the same device selection;
- the same chat template mode;
- the same scheduler/KV settings unless a later probe explicitly varies one dimension;
- exact driver version.

Before stress:

1. `GET /v1/models` or equivalent model-status probe succeeds.
2. one ordinary chat completion succeeds;
3. one known-good tool-call request succeeds;
4. record server PID;
5. capture baseline process working set/commit and Intel GPU shared/dedicated memory;
6. capture the first `PipelineMetrics` line after the request.

If baseline behavior is already regressed, stop. That is not a containment result.

## 8. Natural multi-turn/tool-heavy reproduction

Use the same NovaClaw/agent workload that naturally produced the fault. Do not create an intentionally out-of-bounds GPU kernel or any synthetic device-corruption workload.

For **every turn**, record:

```text
turn index
prompt/input tokens
generated tokens
tool count
rendered tool-schema bytes if available
sampling parameters (do_sample / temperature / top_p / top_k)
prefix-caching setting
PipelineMetrics.requests
PipelineMetrics.scheduled_requests
cache_usage
kv_cache_size_in_bytes
process working set / committed bytes
GPU dedicated/shared memory
HTTP status / finish reason
exact nested runtime exception, if any
```

The first naturally occurring fault is the primary evidence event.

## 9. Containment acceptance after a natural fault

For a fault matching the frozen classifier/policy, all of these are expected:

1. server PID remains alive;
2. log contains `Contained LLM executor runtime fault` with normalized class and original exception;
3. no subsequent `pipe->step()` occurs on that quarantined executor;
4. the in-flight request returns/terminates instead of hanging indefinitely;
5. a new request to the same model fails quickly with server-side unavailability, not `400 INVALID_ARGUMENT`;
6. an unrelated server endpoint still responds;
7. if another independent model/servable is loaded, it remains usable;
8. there is no parser/tool-call fabrication during the failure;
9. process does not enter a high-CPU exception/retry loop.

### Known sketch gap: model readiness

The sketch currently quarantines the executor and rejects requests, but it does **not yet propagate the breaker state into the global model-manager readiness/status owner**. Therefore `/v1/models` or another readiness surface may still advertise the model as available after the breaker trips.

Record that result explicitly as:

```text
READINESS_DEMOTION: PASS | FAIL_EXPECTED_SKETCH_GAP
```

Do not hide it and do not mark the overall containment contract production-complete while this remains open.

## 10. Failure handling semantics to verify

Explicit context-fatal messages should be contained for any model:

```text
CL_OUT_OF_RESOURCES
clFinish / cl_finish failure
device lost
CL_DEVICE_NOT_AVAILABLE
```

Ambiguous execution messages should be contained only under Gemma4 breaker policy:

```text
could not execute a primitive
primitive_onednn_base...
```

These must **not** trip the breaker:

```text
finish_reason=length
normal STOP
invalid max_tokens
invalid/malformed tool call
parser validation error
ordinary client disconnect/cancel
```

Unknown exceptions outside the frozen classifier retain the existing fail-fast behavior in this sketch. That is deliberate scope control, not a claim that `exit(1)` is philosophically wonderful.

## 11. Root-cause differential only after containment evidence

Once the RC2 containment build has evidence, use the **same exact source SHA and workload** with RC1:

```powershell
pwsh -NoProfile -File .\scripts\gemmamonster\test-stable-source.ps1 `
  -RuntimeProfile known-good-rc1 `
  -Gemma4TokenizerPath "<SAME-GEMMA4-TOKENIZER-PATH>"

pwsh -NoProfile -File .\scripts\gemmamonster\build-stable-candidate.ps1 `
  -RuntimeProfile known-good-rc1 `
  -Label gpu-fault-containment-sketch-rc1-ab
```

Do not change source between RC2 and RC1 runs.

Then rerun the same turn sequence and compare the first failing transition.

Interpretation:

- RC1 stable, RC2 unstable: strong runtime-regression evidence;
- both fail at comparable turn/shape: weakens a simple RC2-only regression theory;
- failure threshold moves materially: still useful runtime sensitivity evidence, not proof of the exact low-level commit.

## 12. Follow-up falsification matrix

Change **one dimension at a time** after RC1/RC2 A/B:

1. fresh model pipeline/process before each equivalent turn sequence;
2. prefix caching disabled;
3. `do_sample=false` with all other generation controls fixed;
4. tool-heavy large prefills followed by a tiny request;
5. equally large tool-less prompts;
6. lower output budget without changing input history;
7. lower context/history without changing tool schema.

Interpret conservatively:

```text
requests == 0 + retained memory/cache grows turn-over-turn
    -> supports resource-lifetime/retention leak

memory/cache returns to baseline + specific shape/transition still faults
    -> supports kernel/shape/reuse corruption over simple leak

tool-heavy -> tiny request faults but equally large tool-less does not
    -> argues against capacity alone

prefix caching OFF removes the fault
    -> supports prefix/block lifetime/reuse

do_sample=false materially changes failure threshold
    -> supports sampling/kernel-path sensitivity
```

None of these observations alone licenses the phrase `root cause fixed`.

## 13. Required local-agent report

Commit or return a report containing exactly:

```text
SOURCE_HEAD_TESTED:
SOURCE_TREE_TESTED:
HOT_PARENT:
RUNTIME_PROFILE:
OPENVINO_SHA:
GENAI_SHA:
TOKENIZERS_SHA:
GPU_DRIVER:
OVMS_EXE_SHA256:

SOURCE_CONTRACTS:
BUILD:
BASELINE_CHAT:
BASELINE_TOOL_CALL:
FAULT_REPRODUCED:
FAULT_CLASS:
FAULT_FIRST_VISIBLE_LAYER:
SERVER_PID_SURVIVED:
IN_FLIGHT_REQUEST_TERMINATED:
SAME_MODEL_REJECTED_AFTER_TRIP:
UNRELATED_ENDPOINT_SURVIVED:
UNRELATED_MODEL_SURVIVED:
READINESS_DEMOTION:
NO_EXECUTOR_RETRY_LOOP:

FAULT_TURN:
PROMPT_TOKENS:
GENERATED_TOKENS:
TOOL_COUNT:
TOOL_SCHEMA_BYTES:
PIPELINE_REQUESTS:
SCHEDULED_REQUESTS:
CACHE_USAGE:
KV_CACHE_BYTES:
PROCESS_MEMORY:
GPU_MEMORY:
SAMPLING_CONFIG:
PREFIX_CACHE_CONFIG:

FIRST_NESTED_EXCEPTION:
FULL_LOG_PATH:
CANDIDATE_PATH:

RC1_AB_PERFORMED:
RC1_RESULT:
RC2_RESULT:

OVERALL:
```

Allowed `OVERALL` values for this sketch:

```text
SKETCH_BUILD_FAILED
SKETCH_CONTRACT_TEST_FAILED
SKETCH_BASELINE_REGRESSION
SKETCH_CONTAINMENT_FAILED
SKETCH_CONTAINMENT_PASS_READINESS_GAP
SKETCH_CONTAINMENT_PASS
ROOT_CAUSE_DIFFERENTIAL_INCONCLUSIVE
ROOT_CAUSE_DIFFERENTIAL_POINTS_TO_RUNTIME
```

Do not use `PRODUCTION_ACCEPTED` in this branch.

## 14. Stop conditions

Stop and report evidence rather than patching further if:

- first failure is not in the frozen fault taxonomy;
- the build requires changing runtime pins or source beyond this branch;
- the process survives but request readers still wedge;
- unrelated models/endpoints become unusable;
- memory/cache evidence contradicts the working retention hypothesis;
- RC1/RC2 results contradict the expected runtime-regression theory.

Contradicting the hypothesis is a useful result. Editing the experiment until it agrees with us is merely a more expensive way to lie.
