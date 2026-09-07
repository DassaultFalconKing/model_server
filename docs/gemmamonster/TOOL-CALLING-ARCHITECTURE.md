# GEMMAMONSTER Gemma4 tool-calling architecture

Date: 2026-09-07
Status: LEADING ARCHITECTURE CONTRACT

## Authority and intent

GEMMAMONSTER targets Google Gemma4 native function-calling syntax on OVMS/OpenVINO GenAI while presenting OpenAI-compatible request/response semantics to local agents.

Authority order for protocol behavior:

1. Google Gemma4 protocol and canonical chat template;
2. OpenVINO GenAI structured-output primitives actually available in the target build;
3. xgrammar semantics used by OpenVINO GenAI;
4. OVMS request/response contracts;
5. peer runtimes such as llama.cpp/vLLM as implementation comparators.

Peer runtimes may motivate a compatible mechanism but do not redefine Google syntax.

## Canonical native Gemma4 call envelope

```text
<|tool_call>call:<tool-name>{<native Gemma4 arguments>}<tool_call|>
```

Canonical native strings use:

```text
<|\"|>...<|\"|>
```

Arguments may recursively contain objects, arrays, strings, null, booleans and numbers.

## End-to-end call graph

```text
OpenAI Chat Completions / Responses request
        |
        v
OpenAIApiHandler / endpoint parser
        |
        +--> request.toolChoice
        +--> request.parallelToolCalls (default true)
        +--> request-visible tool/schema map
        |
        v
GenerationConfigBuilder
        |
        v
Gemma4GenerationConfigBuilder
        |
        +--> none: no tool structural config
        +--> auto: TriggeredTags, trigger <|tool_call>, at_least_one=false
        +--> required/named: mandatory TagsWithSeparator
        +--> parallel=true  -> stop_after_first=false
        +--> parallel=false -> stop_after_first=true
        |
        v
chat_template.jinja application
        |
        v
OpenVINO GenAI + xgrammar generation
        |
        v
raw Gemma4 output
        |
        v
OutputParser phase routing
        |
        +--> reasoning -> Gemma4ReasoningParser
        +--> tool region -> Gemma4ToolParser
        +--> content
        |
        v
OpenAI-compatible deltas / response serializer
```

## Generator responsibility

The generator owns **what the model is allowed to emit**, not how malformed historical variants are recovered.

### none

No tool structural grammar is active.

### auto

`auto` is lazy/triggered, not eager mandatory tool generation.

Conceptually:

```text
free generation
    |
model emits <|tool_call>
    v
request-visible structural tool tags + exact request JSON Schema
    |
completed tag
    v
free generation again, unless stop_after_first terminates the tool region
```

OpenVINO representation:

```text
StructuredOutputConfig::TriggeredTags
trigger: <|tool_call>
at_least_one: false
stop_after_first: !parallel_tool_calls
```

This preserves direct prose/no-tool answers while constraining the model once it enters a native tool-call boundary.

### required

At least one tool call is mandatory. Optional Gemma4 reasoning may precede the mandatory tool sequence if that reasoning contract is enabled by the builder. The request must not silently fall back to unconstrained prose if hard structured-output validation fails.

### named

Same hard contract as required, but only the selected request-visible tool may be emitted.

## `parallel_tool_calls`

OpenAI request state:

```text
absent -> true
true   -> true
false  -> false
other  -> InvalidArgument
```

Generation mapping:

```text
true  -> stop_after_first=false
false -> stop_after_first=true
```

Semantics:

```text
auto + true      -> zero or more calls
auto + false     -> zero or one call
required + true  -> one or more calls
required + false -> exactly one call
named + true     -> one or more calls, selected name only
named + false    -> exactly one selected call
```

The Responses API must serialize the actual request policy rather than hard-code `true`.

## Validation fallback responsibility

Gemma4 hard choices are model-specific fail-closed contracts.

The generic builder must not acquire Gemma-specific behavior. The intended abstraction is a model-builder policy hook whose default preserves historical generic fallback behavior while Gemma4 may override it for hard tool choices.

This separation is required so fixes for Gemma4 do not silently alter Hermes or other generation builders.

## Template responsibility

The deployment pack chooses and pins the exact Google canonical `chat_template.jinja`. OVMS applies the model-directory template. The parser/generator must not embed a competing private prompt protocol.

See [`TEMPLATE-CONTRACT.md`](TEMPLATE-CONTRACT.md).

## Parser responsibility

The parser consumes raw model output and turns only strongly anchored native/accepted compatibility syntax into tool deltas.

It must:

- preserve recursive argument structure;
- produce valid JSON arguments;
- validate request-visible tool names;
- preserve ordinary prose that merely resembles a call;
- maintain equivalent unary/streaming behavior across transport splits;
- never repair malformed output by inventing unobserved semantic structure unless a future explicit contract authorizes such repair.

See [`PARSER-CONTRACT.md`](PARSER-CONTRACT.md).

## Boundary ownership

For debugging, classify the first broken boundary:

```text
A  API request parsing / OpenAI contract
G  generation constraint policy
T  template / rendered prompt
M  raw model generation
P  parser
S  streaming accumulator / serialization
W  wiring: wrong builder/parser/schema map selected
E  environment/build/runtime provenance
```

Fix the first wrong boundary. Do not compensate for a generator defect by broadening the parser, or for a parser defect by rewriting the template.

## Deliberately separate concerns

Not part of this architecture contract unless separately approved:

- grammar caching/performance optimization;
- synthetic recovery of structurally truncated calls;
- teaching the generator compatibility variants that only the parser tolerates;
- replacing the canonical Google template with model-card prompt folklore;
- using old runtime evidence as proof for a new source head.
