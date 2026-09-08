# Draft upstream PR description: Gemma4 tool-calling hardening

## Summary

This PR hardens Gemma4 tool calling in OVMS at the two existing model-specific extension points:

- **generation policy** in `Gemma4GenerationConfigBuilder`;
- **native output parsing** in `Gemma4ToolParser`.

The goal is to make OpenAI tool-choice semantics reliable without forcing the complete Gemma4 assistant response into a generic JSON grammar.

The key generation change is lazy structured generation for `tool_choice=auto`: Gemma4 remains free to reason or answer normally until it emits its native `<|tool_call>` marker. At that point OpenVINO GenAI/xgrammar constrains the continuation to request-visible tool names and the original JSON Schema for the selected tool.

Conceptually:

```text
none
  -> no tool constraint

auto
  -> free generation
     -> <|tool_call>
     -> constrained tool name + arguments

required
  -> mandatory native tool call

named
  -> mandatory selected tool only
```

## Why this is model-specific

A Gemma4 assistant turn is not a JSON document. It may contain reasoning, normal prose and native tool-call regions such as:

```text
<|tool_call>call:function_name{...}<tool_call|>
```

Only the argument region has JSON-schema semantics. Globally constraining the whole response as JSON would incorrectly block valid reasoning/prose behavior under `auto`.

The implementation therefore keeps Gemma4 protocol framing model-specific while delegating argument validation to the existing OpenVINO JSON-Schema/xgrammar stack.

## Why `TriggeredTags`

This does not introduce a new grammar subsystem.

OpenVINO GenAI already exposes `StructuredOutputConfig::TriggeredTags`, and upstream OVMS already uses the same abstraction in several model-specific tool-calling builders, including Hermes3/Qwen3, Llama3, Phi4 and Devstral.

Gemma4 already has an explicit native activation boundary:

```text
<|tool_call>
```

Using that boundary as a trigger gives the intended `auto` semantics:

> **before trigger: model discretion; after trigger: structural correctness.**

llama.cpp independently uses lazy grammar around the same Gemma4 tool boundary. That is treated as compatibility evidence only; the OVMS implementation uses native OpenVINO mechanisms and copies no llama.cpp parser, PEG or sampler code.

## Parser hardening

OVMS already has a dedicated `Gemma4ToolParser`. The parser changes harden that existing extension point for native Gemma4 output rather than adding a new parser architecture.

The parser contracts cover:

- recursive arrays and objects;
- preservation of bool/null/integer/float types;
- Gemma4 native string representation;
- bounded malformed-call recovery;
- reasoning-to-tool transitions;
- request tool-registry validation;
- unknown functions not being promoted to executable calls;
- streaming/incomplete native values.

The intended safety rule is:

> **Tolerance applies to serialization, not to execution authority.**

The parser may recover strongly anchored native serialization variants, but it does not fuzzy-match tool names or search arbitrary prose for executable `call:` fragments.

## Why Generator and Parser changes are both needed

Parser hardening cannot repair generation-policy failures.

If `tool_choice=required` ends as prose-only output, no parser can reconstruct a missing call. Likewise, a parser should not rewrite a wrong named function or invent schema-valid arguments that the model did not emit.

Responsibility is therefore split as:

```text
generation correctness
    -> Generator / xgrammar

representation recovery
    -> Parser

execution authorization
    -> request registry + Parser
```

## Scope and blast radius

The lazy-auto change is localized to the Gemma4 generation builder and its contracts. It reuses existing OpenVINO structured-generation primitives and does not change sibling model-builder semantics.

At the lazy-auto implementation point (`80b885281443d7b0fd5f3a2f71237a8524d69b04`), no parser files were changed by that patch.

The working branch has since continued with Generator hardening, including carrying OpenAI `parallel_tool_calls` into structural-tag repetition policy. Those later changes must be reviewed and accepted on their own exact head rather than borrowing earlier runtime evidence.

## Evidence and acceptance boundary

The accepted predecessor/runtime evidence is pinned to:

```text
fea1a5f1c2640aa60fe6a840d3f62b38fb7b7767
```

The lazy-auto implementation point is:

```text
80b885281443d7b0fd5f3a2f71237a8524d69b04
```

These are intentionally not conflated.

The lazy-auto handoff records the implementation and contract evidence, but target Windows/Arc runtime acceptance for that exact implementation was still pending. In particular, the existing predecessor 100/100 result is **not** claimed as evidence for the later lazy implementation.

Required runtime acceptance for the final exact head includes:

- `auto` direct prose/no-tool response;
- `auto` natural tool use;
- schema-pressure case proving invalid enum values cannot escape after the trigger;
- reasoning -> prose and reasoning -> tool;
- `required` and named hard-choice behavior;
- `parallel_tool_calls=true/false` call-count behavior;
- streaming tool-call deltas;
- chained tool-response continuation;
- proof that structured-output validation did not silently fall back to unconstrained generation.

## Review framing

This PR is best understood as filling a Gemma4-specific integration gap using mechanisms already native to OVMS:

```text
canonical Gemma4 protocol
    -> existing Gemma4 builder/parser extension points
    -> existing OpenVINO structured-generation backend
    -> bounded model-specific implementation
```

The resulting design is:

> **Canonical Generator. Tolerant but execution-strict Parser.**
