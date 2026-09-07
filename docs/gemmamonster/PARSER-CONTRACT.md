# GEMMAMONSTER Gemma4 parser contract

Date: 2026-09-07
Status: LEADING PARSER CONTRACT

## Scope

This document defines the parser semantics that the clean fork-main integration must preserve. It intentionally separates canonical generation syntax from parser-only tolerance for observed deviations.

The parser may be more tolerant than the generator/template, but tolerance must be strongly anchored and must never turn ordinary prose into executable tool calls.

## Canonical input

Primary native call form:

```text
<|tool_call>call:<tool-name>{<native arguments>}<tool_call|>
```

Canonical native strings:

```text
<|\"|>...<|\"|>
```

The generator/template should target canonical syntax even when the parser accepts a compatibility variant.

## Core invariants

The parser must:

- parse recursive objects and arrays;
- preserve null, boolean, integer and floating-point types;
- convert native Gemma4 values into valid JSON arguments;
- treat structural characters inside strings as data;
- preserve Windows-path/backslash fidelity after JSON serialization;
- validate tool names against the request-visible registry before producing executable tool calls;
- keep unary and streaming outcomes equivalent for complete generated output;
- hold partial structural markers until enough bytes/tokens exist to decide whether they are real boundaries;
- preserve ordinary prose at EOF when a complete tool-call structure never materializes;
- fail safely on malformed/truncated calls instead of inventing semantic structure.

## Anchoring rule

`call:` is not globally executable syntax.

Tool parsing begins only from parser-owned/accepted boundaries such as:

- canonical `<|tool_call>` entry;
- explicitly accepted anchored compatibility forms;
- a parser-owned reasoning → tool transition where the call preamble is structurally expected.

Ordinary assistant content containing text like `call:foo{...}` must not become a tool call merely because the substring exists.

## Compatibility inputs currently intended to remain parser-only

Subject to the clean-port investigation confirming the exact implementation, current tolerated forms include:

```text
<|tool_call>:name{...}
<|tool_call>call:name(...)
call:name{...} immediately after an accepted Gemma4 reasoning boundary
```

These are compatibility/recovery inputs, not alternate generator targets.

## Numeric-looking scalar hardening

A native scalar must not be sent to RapidJSON as `RawValue` merely because it resembles a number lexically.

Required behavior:

- valid integer/float forms preserve numeric JSON type;
- malformed numeric-looking text never produces invalid response JSON;
- when the native value cannot be validated as the claimed scalar type, the parser must follow an explicit safe path rather than emit syntactically invalid JSON.

The clean-port investigation must identify the minimal current production change that enforces this invariant.

## Bare-call / EOF hardening

Two distinct cases must remain separate:

### Incomplete prose-like call at EOF

If output contains call-like text but never reaches a structurally valid argument container/call boundary, the parser must not silently swallow user-visible prose.

### Fragmented real call

If a real anchored call arrives over multiple chunks and the argument container arrives later, the parser must retain enough state to recover it rather than prematurely classifying it as ordinary content.

Tests must distinguish these two cases.

## Truncation policy

The parser must not synthesize missing closing braces, strings or call delimiters solely to rescue a truncated model output unless a future explicit contract authorizes a specific recovery rule backed by live evidence.

Historical experimental branches that invented missing structure are research evidence, not current authority.

## String and Windows path fidelity

Native strings may contain:

- braces;
- commas;
- JSON-looking substrings;
- backslashes;
- Windows drive paths;
- quote-like content.

Structural scanning must be string-aware. A Windows path must survive the parser → JSON serialization boundary as the same logical string value.

## Tool registry safety

When parser output is routed through the request-aware `OutputParser`:

- unknown tool names are not executable;
- no fuzzy matching is performed;
- one malformed call must not contaminate the name/arguments of another call;
- multi-call ordering and indices remain stable.

## Streaming boundary ownership

The parser owns its start/end markers. Therefore fragmented transport must not leak delimiter bytes into assistant content or tool arguments.

Required split-sensitive boundaries include:

```text
<|tool_call>
<tool_call|>
function name
native string delimiters
escape/backslash sequences
nested object/array boundaries
adjacent multiple calls
```

The final accumulated streaming result should match unary parsing for the same complete raw output.

## Reasoning interaction

Gemma4 reasoning and tool parsing are separate parser capabilities.

A valid reasoning section may transition into a tool call even when observed model output omits an otherwise expected channel marker, but only through an explicit Gemma4 parser-owned capability. That tolerance must not change unrelated reasoning/tool parser combinations.

Reasoning text itself may contain tool-looking prose and must not be executed unless the accepted transition boundary is reached.

## Current hardening source coordinates

The current parser-hardening investigation source is:

```text
fix/gemma4-parser-hardening-post-f36d2d75
d1c21ac1a54d499e644e7619155944a3875fd071
```

Reported hardening scope includes:

- numeric-looking scalar validation;
- incomplete bare-call prose preservation;
- fragmented bare-call recovery;
- Windows path argument fidelity tests;
- fail-closed parser-output invariant corpus;
- reliability harness provenance separation.

The branch itself is not the final integration surface because its history/diff contains far more than the narrow parser scope. The clean-port investigation must extract the minimal production and regression-test delta.

## Files expected to be scrutinized in clean integration

Primary parser files:

```text
src/llm/io_processing/gemma4/gemma4_tool_parser.cpp
src/llm/io_processing/gemma4/gemma4_tool_parser.hpp
```

Boundary-routing files that may contain required parser capability wiring:

```text
src/llm/io_processing/output_parser.cpp
src/llm/io_processing/output_parsing_config.hpp
```

Request/API files touched by historical parser-lineage commits must be classified separately and must not be ported merely because they are present in the branch diff.

## Required focused tests

At minimum preserve regression coverage for:

- canonical recursive tool call;
- nested objects/arrays;
- typed scalars;
- strings containing structural punctuation;
- Windows paths;
- unknown tools;
- numeric-looking malformed values;
- incomplete bare-call prose;
- fragmented real bare call;
- split start/end markers;
- malformed/truncated call safety;
- multiple calls;
- reasoning → tool transition;
- no promotion of unanchored ordinary prose.

Runtime promotion requirements are defined in [`ACCEPTANCE-MATRIX-V1.md`](ACCEPTANCE-MATRIX-V1.md).
