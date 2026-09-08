# Gemma4 chained tool calling: root-cause investigation notes

Status: investigation in progress. The findings below separate code facts from hypotheses. No production fix is accepted until the repeated-trial campaign falsifies alternatives.

## High-confidence code findings

### 1. Gemma4 `auto` currently disables guided tool generation entirely

At production SHA `908bc8b7e3bdd24ddd5eb9b27bbe15bcffb00703`, `Gemma4GenerationConfigBuilder::parseConfigFromRequest()` distinguishes hard choices (`required` and named tool choice) from `auto`.

- `required`/named build structural tool tags and install them in `structured_output_config`.
- `required`/named set `at_least_one=true`.
- `auto` enters the non-hard branch, explicitly resets `config.structured_output_config`, and returns.

Therefore the current Gemma4 `auto` path has two responsibilities left entirely to unconstrained model generation:

1. decide whether to call a tool;
2. emit the complete native tool-call protocol and arguments correctly.

The parser can only act after both have happened.

### 2. This differs from the established OVMS Hermes/Qwen business logic

Current upstream OVMS `Hermes3GenerationConfigBuilder` uses `StructuredOutputConfig::TriggeredTags` when tool-guided generation is enabled (or when `required` is requested):

- trigger: `<tool_call>`;
- normal generation remains free before the trigger;
- after the model generates the trigger, schema-constrained structured generation handles the tool call;
- only `required` sets `at_least_one=true`.

This is the desired semantic split for `auto`:

```text
model owns:  whether to enter tool calling
server owns: valid tool syntax/schema after the tool trigger appears
```

The current Gemma4 builder does not implement this split. This is now the leading code-root-cause candidate for tool-call emission instability after the model decides to use a tool.

Relevant upstream source:
`openvinotoolkit/model_server/src/llm/io_processing/hermes3/generation_config_builder.cpp`

### 3. OpenVINO GenAI provides exactly this trigger primitive

OpenVINO GenAI `StructuralTagsConfig`/triggered structural tags are designed to combine ordinary sampling with structured blocks. When a trigger sequence is generated, decoding switches into structured-output mode for the tagged section and returns to regular sampling afterward.

This means a Gemma4 implementation does not need to choose between:

- fully unconstrained `auto`, and
- forcing a tool call.

It can preserve true OpenAI `auto` semantics while constraining only a tool call that the model has already chosen to begin.

### 4. Sampling can independently vary action selection

`BaseGenerationConfigBuilder` inherits the model generation configuration unless a request overrides it.

- request temperature overrides the model default only when explicitly supplied;
- `do_sample` is enabled when effective temperature > 0 and beams == 1;
- if sampling is active and no explicit request seed exists, OVMS deliberately generates a fresh random seed per request.

Gemma 4 releases and the Wondernutts model family use sampling-oriented defaults (`do_sample=true`, temperature around 0.9-1.0, top-p 0.95 in model examples/config lineage).

Therefore an `auto` request that omits temperature/seed can legitimately vary at the *action-selection* boundary even if parser and structured-call emission are perfect.

This is independent of Finding 1:

```text
sampling variance       -> whether model chooses tool vs prose
missing triggered tags  -> whether a chosen tool action is emitted robustly
parser                   -> whether emitted protocol is recognized
```

The new successful exact-head acceptance used `temperature=0` and `seed=42`, so it simultaneously removed sampling variance while testing the tool-result structuring change. The old intermittent experiment did not preserve exact request payloads. Their individual contributions therefore require the factorial test campaign.

### 5. Parser recognition has a deliberate narrow boundary

The current Gemma4 parser:

- searches for canonical `<|tool_call>` in content;
- accepts the fallback bare `call:` form only exactly at the current parser phase-entry position;
- intentionally does not search for a later bare `call:` inside arbitrary prose.

A model can therefore attempt a noncanonical transition such as:

```text
some prose ... call:tool_name{...}
```

and have it remain content instead of becoming an executable tool call. This is a defensible false-positive guard, but it is a separate measurable failure class.

Raw output with special tokens is required before attributing any failed trial to this parser boundary.

## High-confidence grounding finding

The structured tool-result adapter converts JSON-object tool content to a mapping for compatible Gemma4 templates. The native Gemma4 template then renders its leaves as structured response fields rather than a single escaped JSON blob.

The accepted live chain demonstrated an important asymmetric result:

- exact authoritative commit SHA propagated byte-for-byte through the next tool call;
- surrounding model-generated artifact claims, hashes, paths and classifications could still hallucinate.

So the useful abstraction is not "tool use eliminates hallucination". It is:

```text
authoritative structured variables can form a high-fidelity data channel
inside an otherwise probabilistic semantic generation channel
```

This motivates extending the exact channel to IDs, hashes, paths, counts, versions, enums, timestamps and provenance-aware nested scalar leaves.

## External protocol evidence

Google's Gemma 4 function-calling guidance recommends appending tool execution results as structured `tool_responses`, specifically so the chat template emits native Gemma response syntax such as:

```text
response:get_current_weather{temperature:15,weather:<|"|>sunny<|"|>}
```

Gemma 4 prompt-format documentation defines dedicated tool-call and tool-response control tokens and treats tool execution/injection as an explicit stage of the model lifecycle.

This aligns with the structured-tool-result change already accepted locally.

## Research alignment

### Repeated-run reliability, not one-shot PASS

- `tau-bench` introduced `pass^k` because tool agents are highly inconsistent across repeated executions; reported `pass^8` can collapse even when pass@1 looks respectable.
- BFCL V3/V4 separates single-turn syntax, multi-turn action/state behavior, hallucination and agentic evaluation.
- ReliabilityBench extends this idea to production-like repeated execution, semantic perturbations and tool faults.

This supports our test campaign's repeated trials and stage-specific failure taxonomy.

### Argument grounding must be evaluated separately from schema correctness

- SAAG (Structured Agent Assessment and Grounding, 2026) explicitly decomposes registry conformance, structural completeness and argument grounding; it notes that a model can choose the correct tool and still hallucinate argument values.
- ToolSandbox and related stateful-tool benchmarks identify state dependency/canonicalization as distinct hard problems.
- Evidence-grounded agent work similarly argues that tool access alone does not make generated claims descendants of authoritative evidence.

This directly matches our observation: correct second tool + exact SHA + hallucinated ungrounded siblings.

### Tool-choice uncertainty is a real model boundary

Recent probing work (`Tool Calling is Linearly Readable and Steerable in Language Models`, 2026) reports that wrong calls concentrate when the model's internal top-tool margin is small, and that multi-turn transfer is more fragile than single-turn tool selection. This supports treating action selection as a probabilistic model decision rather than a parser property.

### Constrained decoding helps syntax but must not swallow action selection

- TOOLDEC shows finite-state constrained decoding can eliminate tool syntax errors.
- OpenVINO GenAI explicitly documents trigger-based structural tags for function calls.
- `Constraint Tax in Open-Weight LLMs` reports that applying global JSON-schema constraints together with tool calling can suppress tool invocation by masking action tokens.

Therefore the candidate fix is **not** "put the whole auto turn under JSON grammar". The promising design is trigger-scoped structural generation: leave tool-vs-text choice free, constrain only after the canonical Gemma4 tool trigger.

## Current root-cause decomposition

```text
AUTO TOOL RELIABILITY
    |
    +-- A. action selection
    |      model decides tool vs ordinary answer
    |      affected by prompt/state/thinking/sampling/temperature/seed
    |
    +-- B. protocol emission
    |      once tool is chosen, generate canonical Gemma4 call
    |      CURRENT GAP: Gemma4 auto resets structured_output_config
    |      candidate: TriggeredTags after <|tool_call>
    |
    +-- C. parser recognition
    |      recognize and validate emitted protocol
    |      current parser intentionally rejects some noncanonical bare-call positions
    |
    +-- D. argument grounding
           exact authoritative values vs semantic invention
           structured tool facts already show high exact-value fidelity
```

## Immediate falsifiable hypotheses

- **H1**: `auto` with `temperature=0` has materially higher action-selection repeatability than inherited/positive-temperature sampling.
- **H2**: conditional on canonical `<|tool_call>` appearing in raw generation, current parser recognition is near-deterministic and substantially more reliable than overall `auto` success.
- **H3**: adding Gemma4 trigger-scoped structural tags will reduce malformed/bad-argument tool attempts without forcing tool invocation or reducing legitimate text answers.
- **H4**: grounded exact-value fidelity conditional on an intended parsed call is substantially higher than full semantic payload correctness.
- **H5**: extending structured response leaves to IDs, paths, counts, enums, timestamps and nested scalar values preserves exact values better than free-text reconstruction.

See `docs/gemma4/local-agent-grounded-facts-test-handoff.md` for the required test campaign. Production code must remain untouched until the campaign separates H1/H2/H3.