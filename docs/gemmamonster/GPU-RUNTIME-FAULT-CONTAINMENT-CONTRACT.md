# GEMMAMONSTER GPU Runtime Fault Containment Contract

Status: **FROZEN FOR SKETCH IMPLEMENTATION**

Frozen against hot-line parent: `local/build-gemmamonster-2026.4-dc668c1 @ 4e2e71a0b1dbfae453f75ae069ef424248c9740a`.

This document freezes fault-containment semantics before implementation. It does **not** declare the underlying Intel GPU/OpenVINO defect fixed. Containment and root-cause remediation are separate changes.

## 1. Observed failure boundary

The observed runtime chain is:

```text
LLMExecutorWrapper::run
  -> ContinuousBatchingPipeline::step
  -> OpenVINO InferRequest::_impl->infer
  -> Intel GPU / oneDNN primitive execution
  -> dnnl::error / OpenVINO exception
  -> LLMExecutorWrapper catch(std::exception)
  -> exit(1)
```

At the pinned RC2 OpenVINO source, the first visible low-level execution boundary is `_prim.execute(stream.get_onednn_stream(), _args[net_id])`. The later `OPENVINO_THROW(err.what())`, `InferRequest::infer()` wrapper, and OVMS logger are propagation boundaries, not proof of the original corruption site.

`CL_OUT_OF_RESOURCES` MUST NOT be renamed to `OOM` without evidence. The pinned Intel GPU plugin documents at least two classes behind that status: insufficient resources and out-of-bounds GPU kernel access. It also warns that subsequent OpenCL calls can hang after this fault class.

## 2. Contract A: GEMMA4_LOCAL_RUNTIME_BREAKER

### Purpose

A context-fatal GPU/runtime fault in one Gemma4 model instance MUST NOT terminate the OVMS process and MUST NOT permit reuse of a potentially poisoned GenAI/GPU execution context.

### State model

```text
HEALTHY -> TRIPPED -> RECOVERY_REQUIRED
```

The first sketch deliberately has no automatic `HALF_OPEN`, timed reset, or in-place retry. Recovery means constructing a fresh model pipeline/execution context through normal model reload/restart lifecycle.

### Policy boundary

The Gemma4 breaker is a **policy layer**, not the low-level detector. Generic runtime code classifies a runtime exception first. Gemma4 policy decides whether an ambiguous GPU primitive execution failure is conservative enough to quarantine that model instance.

Gemma4 detection in the 2026.4 refit MAY use the configured `tool_parser == "gemma4"` as the bounded model-family signal because that is the explicit Gemma4 protocol integration point in this branch. This is a sketch constraint, not a claim that every future Gemma model will always configure that parser.

### Fault classes

The sketch classifier exposes:

- `NONE`: no runtime-fatal evidence;
- `GPU_EXECUTION_FAILURE`: GPU/oneDNN primitive execution failed, but the message does not prove a poisoned OpenCL context;
- `GPU_CONTEXT_FATAL`: explicit context-fatal signal such as `CL_OUT_OF_RESOURCES`, `clFinish` failure, device loss, or equivalent OpenCL device/resource failure.

An explicit `GPU_CONTEXT_FATAL` is containable for any model using this executor. An ambiguous `GPU_EXECUTION_FAILURE` trips the model-local breaker only when Gemma4 breaker policy is enabled.

### MUST

1. Keep the OVMS process alive after a contained GPU runtime fault.
2. Prevent every subsequent `pipe->step()` through the faulted executor.
3. Mark the affected executor/model instance unusable until recreation.
4. Reject new requests to the tripped instance with a server-side unavailable/internal status, never `INVALID_ARGUMENT`.
5. Make in-flight OVMS read paths observe the fault without waiting forever on a GenAI result queue that can no longer advance.
6. Keep unrelated models/servables/process services alive.
7. Preserve the original nested exception text and normalized fault class in logs.
8. Keep parser, streamer, OpenAI finish-reason, and session-state semantics separate from runtime-fault classification.

### MUST NOT

1. DO NOT call `exit(1)` for a classified contained runtime fault.
2. DO NOT retry `pipe->step()` on the same faulted executor.
3. DO NOT automatically clear the breaker on a timer.
4. DO NOT classify `STOP`, `LENGTH`, request validation, parser errors, malformed tool calls, or ordinary client cancellation as GPU runtime faults.
5. DO NOT fabricate a tool call or convert the runtime failure into parser recovery.
6. DO NOT let persistent session state resurrect the damaged executor.
7. DO NOT claim an ambiguous `could not execute a primitive` message proves physical memory exhaustion.

## 3. Contract B: GPU_EXECUTOR_FATAL_FAULT_CONTAINMENT

### Purpose

The continuous-batching executor is a generic server-side safety boundary. A classified GPU execution-context fault must become model/executor-local unavailability, not process-global death and not a permanently wedged request.

### Required transition

```text
OpenVINO / oneDNN / OpenCL exception
    -> RuntimeFault classifier
    -> executor fault state
    -> stop scheduling this executor
    -> wake/short-circuit OVMS request readers
    -> return server-side failure
    -> keep process alive
```

### Read-path invariant

`GenerationHandle::read_all()` and `read()` are blocking APIs in the pinned GenAI contract. `GenerationHandle::stop()` only guarantees termination after a subsequent pipeline step. Therefore containment MUST NOT rely on `stop()` or `cancel()` alone to wake a request after `step()` itself has failed and the executor is quarantined.

OVMS MUST own a fault signal that can be checked independently of the GenAI output queue. A unary request must not enter an unbounded `read_all()` while the executor may transition to fatal. A streaming request must not perform a blocking read merely because status is `RUNNING`; it should read only when data is available or return to the orchestration loop.

### Unknown exception invariant

This sketch only replaces process termination for classified GPU execution faults. Unclassified programming/runtime exceptions are outside this contract and MUST NOT be silently swallowed as success. The implementation must log them distinctly and preserve existing fail-fast behavior unless a separate contract broadens containment.

## 4. Root-cause diagnosis contract

Current diagnosis is intentionally narrower than the containment contract:

> The observed failure is a context-fatal or potentially context-fatal Intel GPU execution failure surfaced through oneDNN/OpenCL synchronization. It is not yet a proven physical-memory OOM.

Strong current hypotheses, in descending order of usefulness for testing:

1. retained/reused GPU execution state or resource-lifetime corruption across heterogeneous multi-turn/tool-heavy prefills;
2. shape-dependent or sequence-dependent GPU kernel fault/out-of-bounds access whose error surfaces later at synchronization;
3. prefix/KV block retention after logically completed turns;
4. RC2 runtime regression relative to the retained RC1 runtime oracle;
5. sampling-specific GPU path instability;
6. ordinary capacity exhaustion.

No hypothesis becomes root cause merely because it is plausible.

### Required falsification probes

For the same Gemmamonster source and same workload, collect:

- turn number;
- input/prompt tokens;
- generated tokens;
- tool count and rendered tool-schema bytes;
- `PipelineMetrics.requests`;
- `PipelineMetrics.scheduled_requests`;
- cache usage and KV cache bytes;
- process committed/working-set memory;
- GPU dedicated/shared memory when available;
- sampling configuration;
- prefix-caching configuration;
- exact nested runtime exception;
- whether the failing request was large or a small request after large tool turns.

Interpretation rules:

- `requests == 0` while retained allocation/cache monotonically grows: supports lifetime/retention leak;
- allocation/cache returns to baseline but a specific shape/transition still crashes: supports kernel/reuse corruption more than a leak;
- tool-heavy turns followed by a tiny request reproduce while equally large tool-less prompts do not: argues against capacity alone;
- RC1 stable and RC2 unstable with identical source/workload: strongly supports runtime regression;
- prefix caching off eliminates the fault: supports prefix/block reuse;
- `do_sample=false` materially shifts failure threshold: supports sampling/kernel path involvement.

## 5. Runtime A/B authorities

Same source, different runtime identities must be treated as separate experiments.

### RC2 current candidate

- OpenVINO: `227c33757d1ef95d4da506d00686f923fdd2a535`
- GenAI: `7ea2546852a382cd16bd22dea0cfad2db70ed744`
- Tokenizers: `a04accf6282d9b304214b492694b18c3979f667a`

### RC1 retained oracle

- OpenVINO: `61afcb26271140347709138b13d678e8b1b5925c`
- GenAI: `5f7f1278107d7eae3990ce906bbcfcb69ac3397f`
- Tokenizers: `a04accf6282d9b304214b492694b18c3979f667a`

DO NOT change the runtime pin in the containment sketch. Pin selection is a separate root-cause experiment after the same-source A/B evidence exists.

## 6. Upstream evidence anchors

- OpenVINO issue `#35723`: Gemma4 on Intel GPU reaches several conversation turns and then can fail with `CL_OUT_OF_RESOURCES`; CPU did not show the same failure in the reporter's tests; both iGPU and dGPU were affected; sampling configuration changed stability.
- Intel GPU plugin pinned RC2 `ocl_common.hpp`: `CL_OUT_OF_RESOURCES` may represent insufficient memory or kernel out-of-bounds access and can leave later OpenCL calls unsafe/hanging.
- Pinned GenAI `GenerationHandle`: `read()` and `read_all()` are blocking; `stop()` completes after a subsequent pipeline `step()`.

These anchors motivate the contracts. They do not prove the final root cause of the local Arc 140V failure.

## 7. Sketch acceptance gates

The sketch is acceptable for local validation only when all of the following hold:

1. classifier contract test passes;
2. Gemma4 ambiguous primitive fault trips the model-local breaker;
3. explicit `CL_OUT_OF_RESOURCES` trips generic executor containment;
4. a contained fault does not call `exit(1)`;
5. a faulted executor is never stepped again;
6. new requests to the faulted model return server-side unavailability;
7. unary and streaming read paths cannot block forever solely because the executor was quarantined;
8. ordinary parser/validation/finish-reason behavior remains unchanged;
9. local Windows RC2 build completes;
10. live Gemma4 multi-turn/tool workload confirms process survival after a naturally occurring fault or a safe deterministic test seam;
11. another unaffected endpoint/model remains usable after the Gemma4 breaker trips.

Until gates 9-11 are executed on the Intel Arc host, this branch is **SKETCH / NOT PRODUCTION ACCEPTED**.
