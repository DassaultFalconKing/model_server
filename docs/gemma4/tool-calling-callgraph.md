# Gemma4 tool-calling call graph

This document is the implementation map for the Gemma4/OpenAI tool-calling path in OVMS. It deliberately separates five vectors that are easy to conflate while debugging: **Generator**, **Parser**, **Template**, **repository wiring**, and **official protocol authority**.

## Protocol authority

Google Gemma4 documentation and the canonical Google chat template define the protocol. Peer runtimes (vLLM, SGLang, Dynamo) are compatibility evidence, not the specification.

Primary references:

- Google function calling: https://ai.google.dev/gemma/docs/capabilities/text/function-calling-gemma4
- Google Gemma4 prompt/template semantics: https://ai.google.dev/gemma/docs/core/prompt-formatting-gemma4
- Pinned canonical template used by the deployment pack: `google/gemma-4-12B-it` commit `711c1368e39f1712f48ff0eb7bcdbbb760d52db0`, file `chat_template.jinja`.

Canonical native call envelope:

```text
<|tool_call>call:<tool-name>{<native Gemma4 arguments>}<tool_call|>
```

Canonical native strings use `<|"|>...<|"|>`. Native arguments may recursively contain objects, arrays, null, booleans and numbers.

## Request to response call graph

```text
HTTP /v3/chat/completions or Responses request
    |
    v
OpenAIApiHandler::parseTools()
    |  owns OpenAI request validation
    |  sets request.toolChoice
    |  fills request.toolNameSchemaMap
    v
OpenAIRequest
    |
    +-----------------------------+
    |                             |
    v                             v
GenerationConfigBuilder       initOutputParser()
    |                             |
    | toolParserName=gemma4       | toolParserName=gemma4
    v                             v
Gemma4GenerationConfigBuilder OutputParser
    |                             |
    |                             +--> Gemma4ReasoningParser
    |                             +--> Gemma4ToolParser(tokenizer, toolNameSchemaMap)
    v
InputRequest / GenerationConfig
    |
    v
chat-template application
    |  model-directory chat_template.jinja is authoritative
    |  JINJA: PyJinjaTemplateProcessor
    |  MINJA/tokenizer: tokenizer.apply_chat_template
    v
OpenVINO GenAI generation
    |
    v
raw generated tokens/text
    |
    v
OutputParser phase router
    |
    +--> REASONING
    |      <|channel>thought ... <channel|>
    |      then UNKNOWN
    |      `call:` is accepted only as a Gemma4 preamble entry from UNKNOWN
    |
    +--> TOOL_CALLS
    |      <|tool_call> canonical entry
    |      Gemma4ToolParser recursive native-value parser
    |      request tool registry validation
    |      bounded by <tool_call|>
    |
    +--> CONTENT
    v
Delta / ToolCallDelta
    |
    v
OpenAI-compatible response serializer
```

## Vector 1: Generator

`src/llm/io_processing/generation_config_builder.hpp`

Gemma4 policy:

- `tool_choice=none`: no tool generation grammar.
- `tool_choice=auto`: **native unconstrained Gemma4 generation**. No global tool JSON grammar is installed.
- `tool_choice=required`: fail-closed `StructuredOutputConfig::TagsWithSeparator` from generation position zero.
- named tool choice: same hard constraint, restricted to the named tool.
- response-format grammar and active Gemma4 tool generation are not silently allowed to overwrite each other.

Rationale: constrained decoding in Gemma4 auto mode has shown token-collapse/reserved-token failure modes on complex schemas. Auto selection is model intent plus post-generation parsing; hard OpenAI choices are API contracts.

## Vector 2: Parser

`src/llm/io_processing/gemma4/gemma4_tool_parser.{hpp,cpp}`

Parser v2 properties:

- recursive descent for native objects and arrays;
- typed null/bool/int/float values through RapidJSON;
- `<|"|>` strings and strict JSON strings;
- `{...}` and empirically observed `(...)` argument containers;
- canonical `call:name`, anchored `<|tool_call>:name`, and `call:` preamble after reasoning;
- tool-name syntax validation;
- request tool-registry validation when invoked through `OutputParser`;
- `<tool_call|>` is an absolute malformed-call boundary;
- arguments are emitted only after a complete parse;
- special start-token IDs are resolved by `BaseOutputParser` from the actual tokenizer rather than hard-coded Gemma token IDs.

The parser does **not** fuzzy-match unknown tool names and does not search ordinary content for `call:`.

## Vector 3: Template

OVMS loads `chat_template.jinja` from the model directory with priority. The deployment helper owns which exact template is placed there.

The GEMMAMONSTER diagnostic pack pins Google canonical template revision:

```text
google/gemma-4-12B-it
711c1368e39f1712f48ff0eb7bcdbbb760d52db0
```

The helper records a local SHA-256 sidecar and avoids re-downloading when revision and hash match. Existing model templates are backed up only when replacement content differs.

## Vector 4: Repository wiring invariants

The following information must remain consistent end-to-end:

1. `parseTools()` selects/filter tools and creates `toolNameSchemaMap`.
2. The same map is visible to the generation builder.
3. The same map is passed to `OutputParser` and therefore `Gemma4ToolParser`.
4. `toolParserName=gemma4` selects both the Gemma4 generation policy and Gemma4 output parser.
5. The rendered prompt must use the same model-directory template that was validated/injected by the deployment pack.

A failure should be classified at the first boundary where evidence becomes wrong:

- **G** generator / structured-output policy
- **T** template / rendered prompt
- **M** raw model output
- **P** parser
- **W** repository wiring / wrong implementation selected or data not propagated

## Vector 5: Official documentation conformance

Acceptance tests should prefer canonical Google behavior. Tolerated peer-runtime variants are accepted only when they are strongly anchored and cannot convert ordinary assistant prose into executable calls.

The parser may be more tolerant than the canonical serializer, but the generator/template should target canonical output.
