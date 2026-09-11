# GEMMAMONSTER Agent Negative Contract

Status: mandatory. These are forbidden inferences unless contradicted by direct evidence.

The purpose of this document is to ground coding agents with falsifiable negative constraints. Broad positive goals such as "preserve semantics" are insufficient for refit work.

## Ref provenance

DO NOT infer refit completeness from Git ancestry.

DO NOT treat `9a1626260614f68a6282b6799842d5152f0dcdff` as a direct byte-level descendant or backport of the accepted 2026.5 line.

DO NOT infer that a branch called `latest`, `stable`, `known-good`, or `refit` still points to the SHA recorded in an older report. Resolve it live.

DO NOT silently substitute the later 2026.5 hardening state for the accepted 2026.5 forward-port point when the distinction matters.

DO NOT move `main`, release refs, freeze refs, tags, or accepted baselines unless explicitly requested.

## Tests and semantic equivalence

DO NOT treat the existence of a similarly named regression test as proof that the same terminal semantics are covered.

DO NOT equate:

`truncated protocol frame + STOP`

with:

`truncated protocol frame + LENGTH`.

DO NOT accept a semantic difference between authority behavior and the current refit merely because both implementations pass their own local unit tests.

DO NOT accept an intentional semantic difference unless it has all applicable evidence:

1. explicit rationale;
2. a source-level regression contract;
3. runtime evidence for runtime-sensitive behavior.

DO NOT declare a refit complete by listing copied or modified files. Prove behavior at the seams between owners.

## Generation and context limits

DO NOT treat `max_tokens_limit` as model context length. It constrains request output/generation budget.

DO NOT conflate `max_tokens`, `max_new_tokens`, `max_length`, model architectural context, prompt token count, scheduler/KV capacity, and harness history limits.

DO NOT claim a 64K context merely because `max_tokens_limit=65536` appears in a graph.

DO NOT classify a `finish_reason=length` response as a parser failure merely because no tool call was emitted. First establish whether generation exhausted the effective output budget before a complete executable frame existed.

DO NOT classify context exhaustion until model limit, effective `max_length`, prompt tokens, output reservation, KV capacity, and harness-side truncation have been distinguished.

## Finish reasons and terminal behavior

DO NOT infer natural model termination solely from public `finish_reason="stop"`.

DO NOT assume parser-finalization `STOP` and GenAI's actual terminal reason are the same fact. In the refit architecture, parser drain/finalization and public finish semantics have separate owners.

DO NOT let `FinishDelta` decide OpenAI `stop`, `length`, or `tool_calls` semantics. The endpoint emitter combines semantic deltas with the actual generation finish reason.

DO NOT convert an incomplete tool frame into an executable tool call by inventing a missing tool name, missing arguments, delimiters, braces, or values.

DO NOT emit `finish_reason="tool_calls"` unless at least one executable tool call was actually parsed/accumulated according to the endpoint contract.

## Parser and streamer ownership

DO NOT move Gemma-specific protocol knowledge above the internal typed `Delta` seam.

DO NOT make Chat Completions or Responses serializers parse raw Gemma4 protocol tokens.

DO NOT make `OVMSTextStreamer` own OpenAI JSON semantics.

DO NOT let both the generic `OutputParser` and Gemma4 tool parser independently own the same literal tool-call boundary.

DO NOT discard, duplicate, or expose a reasoning-to-tool boundary merely because `skip_special_tokens` decode mode changes between parser phases.

DO NOT treat direct tool start before canonical reasoning close as normal Gemma4 protocol merely because recovery tolerates it. Canonical and recovery behavior are separate contracts.

## Session boundaries

DO NOT preserve unfinished parser phase, stream-output cache, endpoint SSE lifecycle, or per-response tool-call correlation state across requests.

DO NOT confuse persistent conversation/session/KV continuity with persistent parser/emitter state.

DO NOT use function name as tool-call identity. Repeated same-name calls are distinct calls and require distinct per-response indices/IDs.

## Runtime failures

DO NOT classify OpenVINO primitive execution failure, GPU allocation failure, Mediapipe cancellation, client reset, or `STREAM_TERMINATED` as a parser failure without evidence that parsing was reached and violated its contract.

DO NOT combine `STREAM_TERMINATED` and `GENERATION_LIMIT` into one root cause merely because both stop an agent loop.

DO NOT assume the 2026.4 RC1 and RC2 OpenVINO/GenAI runtime profiles are behaviorally equivalent because Gemmamonster source is identical.

DO NOT attribute a runtime failure to a source refit until packaged module provenance has been checked.

## NovaClaw / agent-loop investigation

DO NOT propose a production fix for an intermittent NovaClaw agent-loop stop until at least one naturally occurring stopped turn has been captured and classified at the earliest failing layer.

DO NOT substitute the synthetic `max_tokens=1` reproducer for a naturally occurring stalled turn. The synthetic case proves a mechanism, not that the same mechanism caused the field failure.

DO NOT stop tracing at the first public symptom. Trace:

`harness decision -> OpenAI request -> request normalization -> GenerationConfig -> GenAI termination -> streamer -> OutputParser -> model parser -> Delta -> endpoint serializer -> harness continue/stop decision`.

DO NOT patch downstream layers to conceal an upstream failure. A harness workaround may be defense in depth, but it is not a root-cause fix unless the harness owns the first failing transition.

## Code-generation discipline

DO NOT lead a refit review with evidence of similarity. Lead with unproven equivalence and adversarial differences.

DO NOT use prior conversation memory as proof of repository state.

DO NOT say "ported", "preserved", "fixed", "known-good", or "accepted" without naming the exact ref and the evidence class supporting that word.

DO NOT claim completion merely because code compiles or tests pass. Verify the specific behavior requested, at the correct layer, under the correct terminal condition.
