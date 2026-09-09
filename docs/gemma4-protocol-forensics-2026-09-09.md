# Gemma 4 protocol forensics — 2026-09-09

## Scope

This report freezes the current evidence for GEMMAMONSTER's Gemma 4 reasoning/tool-call failure family before the next hardening pass.

Baseline under review:

- repository: `DassaultFalconKing/model_server`
- predecessor branch: `integration/ovms-2026.5-forward-port`
- predecessor SHA: `ad19fc6d3934b5255be34059b07e52e0276e7168`
- hardening branch: `integration/gemma4-protocol-hardening-2026.5`

The objective is **not** to replace the custom Gemma 4 tool parser, reasoning parser, or generation-config builder. The objective is to make their shared protocol contract explicit, canonical on generation, tolerant on parsing, and independently testable.

## Frozen external references

References were re-resolved on 2026-09-09.

| Source | Frozen reference | Relevant evidence |
| --- | --- | --- |
| Google Gemma 4 prompt formatting | `https://ai.google.dev/gemma/docs/core/prompt-formatting-gemma4` | Canonical reasoning is `<|channel>thought\n...<channel|>`; canonical tool request is `<|tool_call>call:...<tool_call|>`; the documented reasoning+tool example closes `<channel|>` before `<|tool_call>`; tool-response history has Gemma-specific assistant-role semantics; raw thought retention is exceptional inside a single tool-calling turn. Page last updated 2026-06-03 UTC. |
| Google Gemini function calling | `https://ai.google.dev/gemini-api/docs/function-calling` | Current function-calling guidance stresses explicit tool definitions, bounded relevant tool sets, validation, and robust error handling. |
| OVMS upstream `main` | `a3a2abf287d5cb52f454bb1a1a55c0346cd44a35` | `PRODUCT_VERSION=2026.5.0`; native `gemma4` tool/reasoning parsers are present. Generic `OutputParser` REASONING handling still primarily closes on the reasoning end tag. |
| vLLM `main` | `e509d32b5a2f3d81dc949ff89f85c4c8f860ae29` | Gemma4 unified parser models Text/Reasoning/Header/ToolCall as one state machine. In Reasoning mode, both reasoning-end and tool-start are recognized. Required/named tool choice deliberately avoids generic JSON structured-output forcing and preserves special tokens. |
| SGLang `main` | `ffe98a4279ba6e42d1f87dc4eeb6edb4887b9ea4` | Reasoning detector infrastructure can use tool-start as an interruption boundary and holds partial marker suffixes; Gemma4 serving preserves special tokens. |
| llama.cpp `master` | `9cf3bf256b5a50a971a636c36dfe974387140687` | Gemma4-specific PEG parser/grammar, native tool syntax, tool-response turn reconstruction, parallel-tool grammar, preserved control tokens, and explicit canonical thought closer. |
| Transformers `main` | `5b7dcb0d36c242d8d85920a81c564ef3a86ca6dd` | Declarative Gemma4 response template separates thinking, repeated tool calls, and content with native delimiters and prefix-aware parsing. |

## What the old failure actually was

The historical adversarial campaign showed an apparent contradiction:

- isolated Gemma4 tool parsing was effectively perfect (`279/279` recognition),
- end-to-end agent turns could still return HTTP 200 with `tool_calls=0`, `finish_reason=length`, and the entire `1024`-token completion budget consumed.

That contradiction disappears once the system is treated as a pipeline rather than three unrelated parsers.

### Root cause A — reasoning/tool ownership boundary

The critical ownership chain is:

`generation -> reasoning parser -> composite output state machine -> tool parser`

A tool parser can be correct and still never see the tool opener. The fragile case is an open reasoning phase where `<|tool_call>` appears before the composite parser has observed the expected reasoning closer. If the reasoning owner consumes or buffers that marker, tool parsing never starts.

The fork already contains the important recovery mechanism:

- `e106b214ba0d6c44640c77caa47dfeefde694389` — model tool start as reasoning boundary
- `52aee8bfe0cb76c68c79708a14009d9a69799e11` — hand off tool opener from reasoning phase
- `5038a8322762e25af65b553913af22afbe5c27c6` — split-boundary regression coverage

**Correction to earlier wording:** Google's current Gemma 4 documentation describes the canonical generated sequence with an explicit `<channel|>` before `<|tool_call>`. Therefore direct `REASONING -> TOOL_START` must be documented as a **tolerant recovery path**, not as the canonical Google serialization.

This distinction matters:

- generator: produce/enforce canonical Google protocol;
- parser: accept a conservative tolerant superset so one missing/late closer or streaming boundary does not destroy a valid native tool call.

### Root cause B — hard/named tool grammar mismatch

The historical failing turn used a named hard choice (`publish_review_evidence`). Old behavior did not give named hard choice exactly the same optional thought-before-tool path as `required`.

The current fork's `Gemma4GenerationConfigBuilder` now classifies both `required` and named choices as `Hard`, restricts named choice to the selected tool, and builds a mandatory grammar that allows:

1. native tool call directly, or
2. canonical `<|channel>thought\n...<channel|>` followed by native tool call.

This is the correct direction. It also matches the lesson from current vLLM: Gemma4 required/named mode must not be replaced by generic forced JSON that conflicts with the model's native `<|tool_call>call:...` syntax.

### Root cause C — sampling was a confounder, not the structural fix

The historical adversarial request used roughly:

- `temperature=0.9`
- `top_p` omitted/null
- `top_k` omitted at request level
- no fixed seed

Google's published Gemma 4 generation configs use the standardized sampling family `temperature=1.0`, `top_p=0.95`, `top_k=64`, sampling enabled.

Sampling can change how often a model enters a long reasoning trajectory and therefore how often a parser boundary bug is exposed. Sampling cannot repair a state machine that loses ownership of a structural marker or a grammar that excludes a valid required/named path.

## Current fork delta audit

### Keep

1. `Gemma4ToolParser`
   - Native Gemma4 syntax support is broader than the minimal upstream parser contract.
   - Existing contract tests cover recursive arrays/objects, booleans, nulls, large numbers, string-delimiter safety, malformed/truncated calls, consecutive calls, buffer release, and streaming split behavior.

2. `Gemma4ReasoningParser`
   - Keep the dedicated parser instead of falling back to Qwen semantics.
   - Keep `toolStartTerminatesReasoning=true`, but define it explicitly as tolerant recovery.

3. `Gemma4GenerationConfigBuilder`
   - Keep Gemma4-native structural tags.
   - Keep named/required as hard choices.
   - Keep fail-closed behavior for hard-choice structured-output validation failure.

### Fix or tighten

1. **Protocol wording and invariants**
   - Remove claims that Google canonically permits an unclosed thought channel before a tool opener.
   - State canonical-vs-recovery behavior in code comments and tests.

2. **Boundary test completeness**
   - Existing tests cover one partial opener split and general complete tool-call splits.
   - Add an explicit test that splits the reasoning-to-tool boundary at every byte of `<|tool_call>` while reasoning ownership is active.
   - Add a canonical explicit-close control case next to the recovery case.

3. **Hard-choice contract tests**
   - Verify `required` and named choice both produce native Gemma4 structural-tag grammar and do not degrade to generic JSON response formatting.
   - Verify named choice limits the available tool set rather than disabling thought.

4. **Special-token ownership**
   - Verify Gemma4 parser phases force special-token visibility even when a caller requests normal special-token stripping.

5. **Multi-turn tool-response contract**
   - Verify the exact Google Gemma4 assistant-role reconstruction for tool call + tool response + final assistant content.
   - Preserve reasoning only inside the documented single model turn with function calls; do not indiscriminately replay raw prior-turn thoughts.

6. **Observability**
   - Keep effective GenerationConfig logging separate from request JSON logging.
   - At trace level, record parser phase, explicit reasoning close, recovery tool-start takeover, tool parser entry, finish reason, and generated token count.

## Protocol invariants to enforce

### Generation invariants

G1. Native Gemma4 delimiters are authoritative.

G2. Canonical thought path closes `<channel|>` before a tool request.

G3. `required` means at least one native tool call; named means at least one call to the selected native tool.

G4. `auto` allows ordinary content until the native tool trigger appears.

G5. Generic JSON structured-output forcing must never replace native Gemma4 tool syntax for required/named calls.

G6. `parallel_tool_calls=false` stops after the first call; true permits further native calls.

### Parsing invariants

P1. Canonical `thought -> <channel|> -> tool` parses correctly.

P2. Recovery `open thought -> <|tool_call>` preserves the reasoning prefix and hands the complete opener to the tool parser.

P3. A partial `<|tool_call>` suffix is held until it is either completed or generation finishes; partial bytes do not leak into reasoning.

P4. Recovery behavior is scoped to Gemma4 semantics and must not alter unrelated reasoning parsers.

P5. Unknown tools are non-executable.

P6. Truncated/malformed calls do not become executable calls.

P7. Native string delimiters shield structural-looking payload text.

### Multi-turn invariants

M1. Tool results are serialized using Gemma4's model-turn/tool-response contract.

M2. Raw reasoning from ordinary completed turns is stripped before later standard turns.

M3. Reasoning associated with calls inside the same tool-calling model turn is retained until that tool interaction is complete.

## Verification matrix

Run the same request corpus against:

1. historical OVMS 2026.4 target `2cb5a9a0e8d22732de2d1c89f52795c2de612a57`,
2. predecessor `ad19fc6d3934b5255be34059b07e52e0276e7168`,
3. `integration/gemma4-protocol-hardening-2026.5` final head.

For each relevant request, run at least:

- historical sampling profile,
- Google canonical `T=1.0 / top_p=0.95 / top_k=64`,
- fixed seed where supported.

Capture **effective** merged GenerationConfig and parser transitions. Incoming JSON alone is insufficient because server defaults can fill omitted sampling values.

## Acceptance criteria

The hardening branch is acceptable only when all of the following are evidenced on the target Windows/OpenVINO machine:

- build PASS,
- existing Gemma4 parser suite PASS,
- new canonical/recovery boundary tests PASS,
- required tool choice PASS,
- named tool choice PASS,
- auto tool/no-tool PASS,
- parallel tools PASS,
- multi-turn tool-response PASS,
- no HTTP 5xx in the acceptance corpus,
- no raw native tool syntax leaked as user-visible content,
- no hard-choice request silently falls back from an invalid structural constraint,
- effective generation settings are recorded with the evidence bundle.

Until those machine results exist, the branch may be *implemented* but must not be called *accepted* or *fixed*.
