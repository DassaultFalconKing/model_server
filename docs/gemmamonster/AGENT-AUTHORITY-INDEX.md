# GEMMAMONSTER Agent Authority Index

Status: mandatory bootstrap authority map for coding and research agents.

Purpose: prevent branch-name folklore, stale chat context, or superficially similar tests from replacing exact source/runtime evidence.

## 1. Resolve live state first

Before using any authority below, resolve the live ref and record the actual SHA. The pinned SHAs below are evidence anchors, not permission to assume a branch has not moved.

At introduction of this index on 2026-09-11, the active operational line used for the known-running 2026.4 RC2 lean candidate was:

- repository: `DassaultFalconKing/gemmamonster_model_server_OVMS`
- operational branch: `local/build-gemmamonster-2026.4-dc668c1`
- pre-bootstrap branch HEAD: `91cbe697f2a94e3014a2efb7e40803208d895af7`
- source authority ancestor: `9a1626260614f68a6282b6799842d5152f0dcdff`
- relation observed: operational HEAD was 9 commits ahead of `9a162626...`, with no commits behind it.

Do not confuse this operational/provenance branch with the architectural refit branch. At the same observation point:

- `integration/gemmamonster-2026.4-latest-refit` resolved to `16df6acd96efea26bfa3d5df8f0c47b71c332b15`.

The architectural branch name remains important provenance, but its branch HEAD must not be treated as the current known-running source merely because the name says `latest-refit`.

## 2. Primary authorities

### A0 — current known-running source baseline

`9a1626260614f68a6282b6799842d5152f0dcdff`

Role:

- source baseline for the current 2026.4 Gemmamonster candidate used in termination investigation;
- contains the single-tag xgrammar multiplicity proof and the stable refit source semantics;
- source tree recorded for that commit: `7237a08cd8fc4bbee3dec4649ca1f01a89be2e6a`.

Do not describe A0 as a direct byte-level backport of the accepted 2026.5 line. It is a selective semantic refit on the 2026.4 runtime envelope.

### A0-runtime — known-running packaged candidate

Observed runtime identity:

- OVMS: `2026.4.0.9a1626260`
- source SHA: `9a1626260614f68a6282b6799842d5152f0dcdff`
- binary SHA256: `e7d8024f4f385b8da5051c343da3ace0fbef65813767efb74c7fccffee80cb0a`
- candidate lineage recorded under the 2026.4 RC2 lean build/provenance documents.

Runtime evidence is not interchangeable with source presence. A source test existing in A0 does not prove the packaged binary passed it.

### A1 — advanced semantic authority

`fde0762ba314dc5f6448726dfce7c533bad9a8a6`

Role:

- accepted advanced Gemma4 generation/tool grammar authority;
- includes repeated same-tool/parallel-tool investigation evidence;
- records an historical 2026.4 `max_tokens=96 -> finish_reason=length -> tool_calls=[]` generation failure class;
- serves as semantic authority together with preceding Gemma4 protocol-hardening ancestry.

Important documented divergence: the sole-tag duplication workaround in A1 was later superseded in A0 by pinned GenAI/xgrammar behavior, where `stop_after_first=false` controls multiplicity. That divergence is acceptable only because it has an explicit rationale and a pinned semantic probe.

### A2 — accepted 2026.5 forward-port point

`2d17e36f39412f18df558c49c6bc4661b833f675`

Role:

- accepted 2026.5 forward-port checkpoint;
- authority for the accepted parser/reasoning/request-policy/build-environment port state before later protocol hardening;
- useful differential reference when asking whether a 2026.5 behavior was lost during the 2026.4 refit.

Do not assume ancestry alone proves that A0 preserved every A2 semantic seam.

### A3 — later 2026.5 protocol-hardening line

`5d995cfafdb2ec90578678aa15714dedebc843b8`

Role:

- later Gemma4 protocol-hardening state after the accepted A2 point;
- useful for studying hardened parser/streamer/prompt-state semantics;
- must not be silently substituted for A2 when the question is specifically about accepted 2026.5 behavior.

### A4 — frozen 2026.4 behavioral known-good

`c48366fee1f10cdf6b5fe3c181522ed0c58fc9fd`

Ref: `freeze/gemmamonster-2026.4-known-good`

Role:

- historical behavioral/runtime oracle for the older 2026.4 line;
- comparison point for regressions and runtime A/B work;
- not the same source state as A0.

### A5 — upstream 2026.4 base before runtime switch

`9eb93f15fecb848d399f17c7a6a6626e5a1498d7`

Role:

- last maintainer OVMS source state used as the 2026.4 refit base before the upstream 2026.5 runtime switch;
- distinguishes inherited 2026.4 substrate from Gemmamonster semantic refits.

## 3. Slice authorities

These commits are high-value semantic witnesses. Resolve the exact commit before relying on it.

- `45ea4a8da56efdaccff11273cb286bbd6f52c3b6` — preserve special-token boundaries across reasoning/tool phase handoff; reconcile previous parser phase before inspecting the current token.
- `7f5fa2b9ae840f095aee8192cc7b4e41bae5bf7f` — repair implicit Gemma4 thought detection by comparing rtrimmed prompt against rtrimmed reasoning tag.
- `646b6f8423d0913f988f85875e2a5012b90588c0` — reconcile hard tool grammar after actual chat-template rendering when prompt ends inside open Gemma4 reasoning.
- `52c6b534dab9cb2cb413eb175541870785cdd2c3` — document direct tool-start takeover as recovery/tolerance, not canonical Gemma4 protocol.
- `5038a8322762e25af65b553913af22afbe5c27c6` — cover post-tool reasoning boundary splits and partial tool-marker holdback.
- `64fd113` — centralized rendered-prompt adaptation authority in the hardening ancestry.
- `7f90275` — bounded bare-call recovery authority in the hardening ancestry.
- `7a13bc8` — acceptance wiring authority in the hardening ancestry.

Short SHAs must be resolved to exact full commits before modification work depends on them.

## 4. Design authorities

Read these when touching their ownership surfaces:

- `docs/gemmamonster/STABLE-2026.4-REFIT-HANDOFF.md`
- `docs/gemmamonster/2026.4-CAPITAL-REFIT-ARCHITECTURE.md`
- `docs/gemmamonster/INTERNAL-EVENT-MODEL.md`
- `docs/gemmamonster/Bericht-Provenance-Descendance-diff.md`
- `docs/gemmamonster/KNOWN-GOOD-TOOL-CALLING-20260911.md`
- `docs/gemmamonster/2026.4-RC2-LEAN-BUILD-PROVENANCE.md`

Key ownership rule from the internal event model:

- model-specific protocol meaning belongs below the typed `Delta` seam;
- endpoint-specific OpenAI wire semantics belong above it;
- `OVMSTextStreamer` owns decoding/special-token preservation/parser delivery, not OpenAI JSON semantics;
- `FinishDelta` by itself does not decide `stop`, `length`, or `tool_calls`.

## 5. Runtime-profile authorities

For the 2026.4 stable refit, source identity and runtime dependency identity are separate facts.

Maintainer RC2 profile recorded in the handoff:

- OpenVINO: `227c33757d1ef95d4da506d00686f923fdd2a535`
- Tokenizers: `a04accf6282d9b304214b492694b18c3979f667a`
- GenAI: `7ea2546852a382cd16bd22dea0cfad2db70ed744`

Historical known-good RC1 A/B profile:

- OpenVINO: `61afcb26271140347709138b13d678e8b1b5925c`
- Tokenizers: `a04accf6282d9b304214b492694b18c3979f667a`
- GenAI: `5f7f1278107d7eae3990ce906bbcfcb69ac3397f`

Do not infer behavioral equivalence between RC1 and RC2 from identical Gemmamonster source.

## 6. Current termination-investigation authority

A diagnostic investigation on the A0 runtime established two distinct failure classes:

1. clean synthetic generation-budget reproducer:
   `max_tokens=1 -> GenerationConfig.max_new_tokens=1 -> GenerationFinishReason::LENGTH -> incomplete <|tool_call> frame -> no executable tool_calls -> OpenAI finish_reason=length`;
2. separate runtime failure observed on another server instance:
   OpenVINO/GenAI `could not execute a primitive` -> Mediapipe cancellation/client reset -> `STREAM_TERMINATED`.

These are independent until evidence proves otherwise.

The synthetic `max_tokens=1` result proves a failure mechanism, not the root cause of naturally occurring NovaClaw stalls. A natural stalled turn must still be captured and classified at its first failing layer before production behavior is changed.

## 7. Authority precedence for investigations

Use the narrowest authority that answers the question:

1. exact failing runtime trace and packaged-runtime provenance;
2. exact source SHA used to build that runtime;
3. accepted semantic authority for the specific slice;
4. design/ownership contract;
5. historical known-good behavior;
6. upstream behavior/documentation;
7. branch names, commit messages, prior chat summaries, and memory only as discovery hints.

A lower item cannot override a contradictory higher item without new evidence.

## 8. Mandatory differential question

For every 2026.5 -> 2026.4 refit review, ask:

> What behavior present in the semantic authority cannot be proven equivalent in the target refit under the same terminal condition, parser phase, chunk boundary, runtime profile, and endpoint path?

In particular, do not treat `truncated frame + STOP` as coverage for `truncated frame + LENGTH`.
