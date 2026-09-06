# Addendum: code-contract probes for root-cause claims

Add narrow tests on the test branch only. Do not change production code to make them pass.

## Probe 1: Gemma4 auto ignores guided-generation enablement

Characterize current production behavior at `908bc8b7...`:

- construct `Gemma4GenerationConfigBuilder` with `enableToolGuidedGeneration=true`;
- provide at least two valid tool schemas;
- set `tool_choice=auto`;
- call `parseConfigFromRequest()`;
- assert/record whether `structured_output_config` exists.

Expected **current characterization** from source reading: absent/reset.

Run the same with `enableToolGuidedGeneration=false`; current auto behavior should be the same.

Then add a separate diagnostic/expected-failure specification (do not patch production) describing the desired future contract:

- auto + guided generation should keep action selection optional;
- once `<|tool_call>` is emitted, a trigger-scoped structural tag should constrain the selected tool call;
- `at_least_one` must remain false for auto.

If the exact GenAI type/API available in this checkout permits constructing `StructuredOutputConfig::TriggeredTags`, compile a test helper that proves the type and desired shape are available without modifying server code.

## Probe 2: required/named remain hard

Verify current hard-choice behavior:

- required + tools => structural config present and at least one tool enforced;
- named + matching tool => only that tool schema/tag is admitted;
- hard choice without tools => fail closed.

This guards against accidentally "fixing auto" by weakening required/named semantics later.

## Probe 3: sampling inheritance

Using a base `GenerationConfig` with positive temperature (prefer the model-family default 1.0 if no exact local model config is available):

- omitted request temperature => effective config retains base temperature;
- explicit request `temperature=0` => sampling is disabled;
- positive temperature + omitted seed => characterize that request processing may assign a fresh nonzero RNG seed;
- positive temperature + fixed request seed => exact seed is retained.

If deterministic unit testing of the randomized seed is awkward, assert only the contract required by source code (nonzero and not caller-specified) and leave cross-request variation to the runtime campaign.

## Probe 4: parser bare-call boundary

Feed the Gemma4 parser equivalent complete outputs and record deltas:

1. canonical `<|tool_call>call:fn{...}<tool_call|>` => parsed tool call;
2. bare `call:fn{...}<tool_call|>` exactly at parser phase entry => accepted fallback if current contract permits;
3. `prefix prose call:fn{...}<tool_call|>` without canonical start token => must not be promoted to executable tool call;
4. `prefix prose <|tool_call>call:fn{...}<tool_call|>` => canonical tag should still be found and parsed.

These distinguish intentional false-positive protection from parser loss of canonical calls.

## Probe 5: exact-fact adapter boundary

Extend/confirm adapter tests for:

- JSON object tool content -> mapping;
- exact SHA/hash/UUID/path/numeric/string lexical leaves preserved;
- non-tool JSON-looking content untouched;
- malformed JSON untouched;
- JSON array/scalar tool content retains current string semantics;
- free-text fake SHA does not overwrite structured SHA.

## Reporting

Return a table:

| Claim | Test | Current result | Supports / falsifies |
|---|---|---|---|

Do not mark a desired-future-contract failure as a repository regression. It is diagnostic evidence for the proposed change.
