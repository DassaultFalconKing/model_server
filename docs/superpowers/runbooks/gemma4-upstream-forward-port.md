# Gemma4 upstream forward-port runbook

This runbook is the authority for carrying the GEMMAMONSTER Gemma4 reliability overlay onto a newer `openvinotoolkit/model_server` head.

## Principle

Always start from the new upstream tree and forward-port the smallest proven overlay. Do not rebase or replay the entire fork history and do not copy old versions of generic OVMS files over a newer upstream. The fork contains both product-independent upstream code and Gemma4 reliability work; treating every historical fork commit as equally authoritative recreates old OVMS around a new version number.

The machine-readable ownership map is `scripts/gemma4/forward-port-manifest.json`.

## Current accepted inputs

- Known-good 2026.4 product line: `c48366fee1f10cdf6b5fe3c181522ed0c58fc9fd`.
- 2026.5 upstream base used by the current candidate: `b935fe8b96a0445f3746297f872b55ed202fa6e5`.
- Current integration branch: `integration/ovms-2026.5-forward-port`.
- OpenVINO/GenAI/Tokenizers versions are owned by the selected upstream tree and checked by `audit-forward-port.ps1`.
- Current working runtime profile on the target machine is **Profile E**. Its contract is `runtime/gemmamonster-ovms-E/profile.json`; it must not be silently replaced by B2/C during forward-port or A/B testing.

After a later candidate is formally promoted, update the manifest's accepted overlay ref and dependency contract in a dedicated evidence-backed commit. Never silently retarget the manifest while porting.

## Runtime profile E contract

Profile E is a first-class part of the acceptance contract because source correctness without the working runtime configuration is not a reproducible result.

Pinned E properties:

- device `GPU`
- pipeline `VLM_CB`
- `max_num_seqs: 1`
- plugin `DYNAMIC_QUANTIZATION_GROUP_SIZE: 0`
- plugin `KV_CACHE_PRECISION: u8`
- prefix caching enabled
- default chat template mode `JINJA`
- `max_tokens_limit: 65536`

The exact working E `cache_size` is not evidenced in the frozen Git tree. Therefore E intentionally leaves that option unset. Do not borrow B2's `0` or C's `8` just to fill the field. If target-machine evidence later establishes the exact E value, pin it in `profile.json`, the launcher and an acceptance evidence commit together.

`Stable` and `PrefixCache` are diagnostic comparison profiles only.

## Ownership classes

`KEEP_OVERLAY` means the local semantic contract is stronger than current upstream and must remain unless upstream passes the same contracts and live reliability campaign. The hardened Gemma4 parser is in this class.

`MANUAL_COMPOSE` means both sides contain valuable behavior. Compare new upstream, previous accepted overlay and current tests. Preserve upstream generic changes while reapplying only the Gemma4 contract. Generator, OpenAI request policy, chat-template caps/analyzer/adapter, session continuity and BUILD wiring are in this class.

`UPSTREAM_OWNED` means use the new upstream implementation by default. Dependency pins, packaging, generic server lifecycle, generic Responses work and generic reasoning-effort support are examples. Do not replace an upstream-owned file with an old fork blob merely because a one-line local fix lives there.

`TEST_ONLY` and `DEPLOY_TOOL` are portable evidence/operations assets. They can normally move intact unless their interfaces changed.

## Bootstrap a future upstream head

Start from a clean accepted worktree with an official `upstream` remote. The helper creates the new branch from the exact fetched upstream SHA, optionally copies only manifest-declared safe paths and prints every file that requires semantic composition.

```powershell
pwsh -File scripts/gemma4/new-upstream-forward-port.ps1 `
  -Version 2026.6 `
  -OverlayRef <exact-accepted-overlay-sha> `
  -ApplySafeCopies
```

The script never commits and never pushes. Its report is written under `tmp/gemmamonster-forward-port/<version>/`.

## Required composition order

1. Port contract tests and evidence tooling first.
2. Port hardened `gemma4_tool_parser.*`.
3. Compose `generation_config_builder.hpp`; preserve new upstream generic generation, speculative decoding and pipeline work.
4. Compose OpenAI request/API policy. Preserve upstream API improvements while keeping hard/named fail-closed semantics and `parallel_tool_calls` request policy.
5. Compose chat-template caps/analyzer/adapter. Gemma4 needs both upstream response-field handling and the guarded tool-response JSON mapping workaround.
6. Compose `servable.*` session continuity without deleting new upstream fields or lifecycle behavior.
7. Preserve/verify Profile E launcher contract.
8. Reconcile BUILD targets and tests.
9. Run the static audit. Build only after `FAIL=0`.
10. Build, launch Profile E, run chained acceptance, then reliability campaign.

## Non-negotiable Gemma4 contracts

The port is not complete if any of these disappear:

- `auto` may emit ordinary prose, but once a Gemma4 tool-call marker begins the call is structurally constrained.
- `required` and named choices cannot fall back to free text because grammar validation failed.
- hard/named tool choice without usable tools fails instead of becoming unconstrained generation.
- `parallel_tool_calls=false` reaches the Gemma4 generation policy and yields one-call structural behavior.
- optional Gemma thought before hard tool calls is represented without an empty `ConstString`.
- nested native Gemma values and lexical number spellings survive parsing.
- bare `call:` recovery is limited to a logical line boundary and validated against the request tool registry.
- Google-style tool results are converted to mapping only when the template expects a mapping and does not iterate content parts with `part.get(...)`.
- upstream `function.response` handling remains present.
- `X-OVMS-Session-ID` preserves durable seed/effective generation configuration across chained turns and restart/resume tests.
- the target-machine working Profile E is used symmetrically in 2026.4/2026.5 A/B unless an experiment explicitly changes exactly one runtime variable.

## Static gate

Run from the repository root:

```powershell
pwsh -File scripts/gemma4/audit-forward-port.ps1 -OutputPath tmp/gemma4-audit.json
```

A missing semantic anchor or wrong dependency pin is `FAIL`. A known local experiment or explicitly delegated patch may be `WARN`. Warnings must be explained in the final acceptance evidence.

## Current known local patch delegated to the machine agent

On the current 2026.5 candidate, `src/llm/apis/openai_responses.cpp` still serializes `parallel_tool_calls` as constant `true` in the Responses endpoint. The request parsing and Chat Completions generation path already carry `request.parallelToolCalls` correctly.

The local agent must make this as a minimal patch against the exact checked-out 2026.5 file:

1. locate the Responses serialization of the `parallel_tool_calls` property;
2. replace only the hard-coded boolean value with the already parsed request policy (`request.parallelToolCalls`, or the exact equivalent in the current surrounding class if upstream renamed access);
3. do not copy the 2026.4 `openai_responses.cpp` over the 2026.5 file;
4. add or update the narrow response round-trip test if the current test does not cover false;
5. run the static audit again and record the dirty/local commit SHA in acceptance evidence.

This patch is intentionally a warning in the manifest, not permission to change unrelated Responses code.

## De-overlay rule

A local workaround may be removed only when the new upstream implementation is contract-equivalent and passes the same parser/generation/template/session tests plus live acceptance. If upstream merely contains code with a similar name, that is not evidence of equivalence.

## Promotion rule

Do not move `main` because the source compiles. Promotion requires exact provenance, static `FAIL=0`, parser/generation/template/session tests, named/required/auto chained tool success, reliability at least equal to the frozen baseline, Profile E parity, and review of every remaining overlay. Keep the 2026.4 freeze untouched until the 2026.5 candidate is accepted on the target machine.
