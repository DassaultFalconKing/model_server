# GEMMAMONSTER Gemma4 generator contract

Date: 2026-09-07
Status: LEADING GENERATOR CONTRACT

## Scope

This document defines the accepted Gemma4 generation-side behavior to preserve when the historical feature branches are clean-ported onto the new upstream-derived fork `main`.

It is a semantic contract, not a requirement to preserve old commit topology.

## Tool-choice state machine

### Disabled

Applies when there are no active tools or `tool_choice=none`.

Expected:

- no tool structural output config;
- no Gemma-specific hard-choice fallback state;
- ordinary response-format behavior remains independent.

### Auto

Applies to `tool_choice=auto` with active tools.

Expected OpenVINO GenAI representation:

```text
StructuredOutputConfig::TriggeredTags
trigger: <|tool_call>
at_least_one: false
stop_after_first: !request.parallelToolCalls
```

Each request-visible tool is represented as a structural tag with:

```text
begin:   <|tool_call>call:<tool-name>
content: JSONSchema(original request schema)
end:     <tool_call|>
```

Required semantics:

- direct prose is legal;
- reasoning before a call is legal when the model/template produces it;
- no tool call is mandatory;
- once `<|tool_call>` is entered, only request-visible tool names and schema-valid arguments are legal;
- with `parallel_tool_calls=true`, later tool triggers/calls remain possible;
- with `parallel_tool_calls=false`, at most one tool call may be produced.

A supported canonical schema that causes the runtime to drop/fallback from the TriggeredTags config is an acceptance failure for the guided-auto lane. The generic fallback mechanism may still exist, but it is not evidence that auto guidance succeeded.

### Required

Applies to `tool_choice=required`.

Expected representation is mandatory structural tool generation, currently `TagsWithSeparator` or an equivalent OpenVINO GenAI/xgrammar structure that preserves the same behavior.

Required semantics:

- at least one request-visible tool call;
- prose-only completion is illegal;
- optional reasoning may precede the mandatory tool sequence;
- `parallel_tool_calls=true` permits one or more calls;
- `parallel_tool_calls=false` permits exactly one call;
- validation failure remains fail-closed.

### Named

Applies to an OpenAI named tool choice.

Required semantics:

- selected name must exist in the request tool registry;
- only the selected name may be generated;
- `parallel_tool_calls=true` permits repeated/multiple calls of that selected tool if the structural representation permits it;
- `parallel_tool_calls=false` permits exactly one selected-tool call;
- validation failure remains fail-closed.

## OpenAI `parallel_tool_calls` request contract

`OpenAIRequest` carries:

```cpp
bool parallelToolCalls{true};
```

Parsing semantics:

```text
field absent                  -> true
"parallel_tool_calls": true  -> true
"parallel_tool_calls": false -> false
non-boolean                   -> InvalidArgument
```

The policy is parsed at the OpenAI API boundary and then carried as request state. It must not be recomputed from model-specific heuristics later in the pipeline.

Both Chat Completions and Responses endpoint paths must honor the same request state.

## Responses serialization contract

The Responses object must report the actual policy:

```cpp
writer.String("parallel_tool_calls");
writer.Bool(request.parallelToolCalls);
```

Hard-coding `true` is incorrect because it makes the response object disagree with the generation policy actually used.

The reviewed narrow fix is represented by:

```text
34c2f23d58e96a2c2ef1b3e2f940909c3131ace5
fix(openai): serialize parallel tool call policy
```

The clean integration may reproduce that semantic change without preserving its branch topology.

## Model-specific validation fallback

Gemma4 hard-choice fail-closed behavior must be localized to the Gemma4 builder rather than stored as generic wrapper state.

Intended abstraction:

```cpp
virtual bool shouldPreserveStructuredOutputOnValidationFailure() const {
    return false;
}
```

with a Gemma4 override driven by parsed hard-choice state.

Required invariant:

```text
Gemma4 required/named -> preserve hard constraint / fail closed
Gemma4 auto           -> not treated as a hard choice
Hermes/other builders -> historical generic fallback behavior unchanged
```

A test must prove this separation directly.

## Response-format interaction

Active Gemma4 tool structural constraints and an independently active `response_format` structural constraint must not silently overwrite each other.

Until an explicit composition design exists, conflicting simultaneous constraints are rejected rather than producing an ambiguous effective grammar.

## Tool/schema registry invariants

Generation must use the request-visible tool registry after OpenAI request normalization/filtering.

For every emitted structural tool tag:

- the function name is a request-visible legal name;
- the original request schema is passed to JSONSchema enforcement;
- unavailable named choices are rejected before generation;
- invalid/empty schemas are rejected according to the selected builder contract.

## Historical source coordinates

Important source commits in the current feature history include:

```text
80b885281443d7b0fd5f3a2f71237a8524d69b04
    first TriggeredTags/lazy auto implementation

bc4cd8c08749d861651aca278d50aa8dbb185789
    auto generation contract tests

158c6c8aa2447c79fe3ce4f7badfe9b5b6916fe7
    base builder model-specific fallback hook

2badb13ec7c954f9fee9093a098139ddd6595f64
    OpenAIRequest parallel policy state

ac5a8deead2e77f644588e88a0cfb1138fbc9c10
    Gemma parallel stop policy + fallback localization

1244577fb30474a9c68a1b83bdb6fc10bad4a046
b705fc19dff874da33141feb763342344072b72e
0cd155a88afbd11feb93b722c9d195a8ee8f463c
    endpoint parsing plumbing

34c2f23d58e96a2c2ef1b3e2f940909c3131ace5
    Responses serialization policy fix
```

These commits are investigation coordinates, not an instruction to cherry-pick blindly.

## Explicitly rejected historical artifact

Do not reproduce the accidental full-file rewrite represented by historical commit:

```text
c1698126b489acee7910e538a4eda8519be7e6f9
```

The subsequent restoration commit returned `openai_responses.cpp` to the correct source before the narrow policy fix. A clean integration must contain only the intended semantic one-line Responses change.

## Required focused regression coverage

At minimum the final clean candidate must prove:

- no-tools / none behavior;
- auto uses lazy/TriggeredTags semantics;
- required/named remain mandatory;
- reasoning before hard tool selection remains legal;
- named selection rejects unavailable names;
- original schemas remain attached to each tool tag;
- `parallel_tool_calls` absent/true/false/non-boolean parsing;
- `stop_after_first` mapping for auto/required/named;
- Responses serialization echoes actual policy;
- Gemma-specific hard-choice fallback does not leak into a non-Gemma builder.

See [`ACCEPTANCE-MATRIX-V1.md`](ACCEPTANCE-MATRIX-V1.md) for runtime gates.
