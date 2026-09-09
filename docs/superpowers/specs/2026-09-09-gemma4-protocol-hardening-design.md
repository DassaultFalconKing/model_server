# Gemma 4 Protocol Hardening Design

Date: 2026-09-09
Branch: `integration/gemma4-protocol-hardening-2026.5`
Predecessor: `ad19fc6d3934b5255be34059b07e52e0276e7168`
Forensic authority: `docs/gemma4-protocol-forensics-2026-09-09.md`

## 1. Purpose

Harden GEMMAMONSTER's custom Gemma 4 protocol stack without replacing its three specialized components:

- `Gemma4GenerationConfigBuilder`
- `Gemma4ReasoningParser`
- `Gemma4ToolParser`

The design treats these as one protocol pipeline with explicit ownership and transition contracts.

## 2. Architectural choice

### Selected approach: specialized components + explicit composite protocol policy

Retain separate generation, reasoning, and tool parser classes. The composite `OutputParser` owns transitions between semantic phases. Gemma4-specific configuration declares the recovery transition that the generic state machine must honor.

Why this approach:

- preserves already-good parser coverage and API boundaries;
- avoids duplicating vLLM's entire unified Rust parser inside OVMS;
- keeps model-specific behavior declarative where possible;
- lets generic `OutputParser` remain reusable while Gemma4 opts into its special boundary behavior;
- minimizes forward-port surface against OVMS upstream.

### Rejected approach: replace the stack with upstream OVMS parsers

Rejected because current upstream still lacks several fork capabilities and does not eliminate the reasoning/tool ownership problem.

### Rejected approach: one monolithic Gemma4 parser

A vLLM-style unified parser is conceptually clean, but would be a larger rewrite with unnecessary regression risk. The existing OVMS architecture already has separate parsers and a composite state machine. The required semantics can be represented without replacing that architecture.

## 3. Canonical generation vs tolerant parsing

This is the central contract.

### Generator

The generator emits/enforces the **canonical Google Gemma 4 protocol**:

```text
<|channel>thought\n
...
<channel|>
<|tool_call>call:NAME{...}<tool_call|>
```

A hard tool choice may also choose a direct native tool call when the model does not use a thought channel.

### Parser

The parser accepts the canonical protocol plus a **conservative recovery superset**:

```text
REASONING + <|tool_call>  => preserve preceding reasoning, transfer opener intact to TOOL
```

This recovery path protects against malformed/edge model output and streaming boundary ambiguity. It is not emitted by the generator and is not described as canonical Google serialization.

## 4. State ownership

The relevant composite states are:

```text
UNKNOWN
  reasoning-start -> REASONING
  tool-start      -> TOOL_CALLS_PROCESSING_TOOL
  ordinary bytes  -> CONTENT

REASONING
  explicit reasoning-end -> UNKNOWN
  tool-start (Gemma4 recovery policy) -> TOOL_CALLS_PROCESSING_TOOL
  partial tool-start -> HOLD
  ordinary bytes -> REASONING

CONTENT
  tool-start -> TOOL_CALLS_PROCESSING_TOOL
  ordinary bytes -> CONTENT

TOOL_CALLS_PROCESSING_TOOL
  tool-end -> TOOL_CALLS_WAITING_FOR_TOOL
  body -> TOOL_CALLS_PROCESSING_TOOL

TOOL_CALLS_WAITING_FOR_TOOL
  next tool-start -> TOOL_CALLS_PROCESSING_TOOL
  content turn -> CONTENT
```

No parser is allowed to consume bytes that semantically begin the next parser-owned phase.

## 5. Generation policy

### `none`

No active tool structural constraint.

### `auto`

Use native Gemma4 tool tags behind a lazy trigger. Ordinary prose remains possible until `<|tool_call>` appears.

### `required`

At least one native tool call is mandatory. Thought-before-tool is permitted only in canonical closed form.

### named tool choice

Treat as the same hard mode as `required`, but build tags only for the selected tool. Naming a tool constrains *which tool* may be called; it must not forbid the model's canonical thought phase.

### Validation failure

Hard choices fail closed. A structural-output validation failure must not silently clear the constraint and continue as unconstrained generation.

## 6. Native syntax policy

Gemma4-native syntax is authoritative:

```text
<|tool_call>call:NAME{key:value}<tool_call|>
```

String payloads use Gemma's `<|"|>` delimiter. The tool parser remains responsible for converting native arguments to OpenAI-compatible JSON arguments.

Generic forced JSON output is not a substitute for native tool-call serialization.

## 7. Multi-turn policy

Google's Gemma 4 format places tool calls and tool responses inside the model/assistant turn representation.

Rules:

1. preserve tool-related reasoning context during a single ongoing function-calling turn;
2. serialize tool responses with the Gemma4 chat-template contract;
3. strip raw completed-turn reasoning from ordinary later conversation history;
4. do not replay arbitrary raw chain-of-thought as normal history;
5. if long-running agents need reasoning continuity, use an application-level summary rather than raw historical thought tokens.

## 8. Streaming policy

Structural markers may be split at any byte/token boundary.

Requirements:

- hold the longest suffix that can still become a relevant control marker;
- do not emit partial `<|tool_call>` bytes as reasoning/content;
- when the marker completes, transfer it intact to the tool parser;
- at end-of-generation, incomplete tool syntax remains non-executable;
- parser recovery must be deterministic across chunk partitions.

## 9. Observability

Trace-level evidence should make parser ownership reconstructable:

- current composite phase;
- decoded chunk and token IDs where already supported;
- explicit reasoning end observed;
- Gemma4 recovery handoff triggered;
- tool parser entered;
- tool parser completed/rejected call;
- finish reason;
- effective merged generation parameters.

Logs are diagnostic evidence, not part of API output.

## 10. Testing strategy

### Unit/contract

- canonical thought-close-tool control case;
- recovery open-thought-tool case;
- every-byte split across the reasoning/tool boundary;
- partial opener never leaks;
- direct native tool without thought;
- required/named/auto/none grammar behavior;
- named restricts tool set;
- parallel vs single call;
- unknown/truncated/malformed calls remain non-executable;
- nested values and structural-looking strings;
- special-token visibility;
- non-Gemma reasoning parser remains unaffected.

### Integration

- Google chat-template rendering;
- tool result reconstruction;
- reasoning continuity inside one tool-calling turn;
- raw thought stripping across ordinary completed turns;
- OpenAI Chat Completions behavior;
- streaming and non-streaming equivalence where applicable.

### Live machine acceptance

Run the frozen adversarial corpus plus CodeSleuth agent prompts on the Windows OpenVINO target. Capture effective config, parser traces, responses, and exact binary/source SHA.

## 11. Non-goals

- no replacement of custom Gemma4 parsers with vLLM/SGLang/llama.cpp code;
- no unrelated parser refactor;
- no new public API unless tests prove it is necessary;
- no attempt to expose hidden reasoning to end users;
- no claim that tolerant recovery is canonical Google formatting.

## 12. Success criteria

The design is implemented when:

- generator remains canonical;
- parser remains tolerant without leaking control markers;
- hard choices are native and fail closed;
- parser and generator contracts are covered by deterministic tests;
- machine acceptance demonstrates stable tool calling under the frozen corpus;
- the evidence differentiates model behavior, server parsing, grammar enforcement, request configuration, and harness behavior.
