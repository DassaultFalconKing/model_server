# Gemma4 `tool_choice=auto` generator port handoff

Date: 2026-09-07

```text
BRANCH: feature/gemma4-llamacpp-auto-generator-port
BASE_SHA: f36d2d758264ac5f371c344c49e485f582b07b5a
IMPLEMENTATION_HEAD_SHA: 80b885281443d7b0fd5f3a2f71237a8524d69b04
```

The handoff document is committed after the implementation, so `IMPLEMENTATION_HEAD_SHA` identifies the exact code-under-test. The final branch head also contains this report commit.

## Implemented

`Gemma4GenerationConfigBuilder` now has an explicit three-way tool constraint policy:

```text
Disabled  -> no tool grammar (`tool_choice=none` or no request tools)
Auto      -> lazy/triggered tool grammar
Hard      -> eager mandatory grammar (`required` or named choice)
```

For `auto`, the builder now creates `ov::genai::StructuredOutputConfig::TriggeredTags` with:

```text
trigger:          <|tool_call>
at_least_one:     false
stop_after_first: false
```

Each request-visible tool remains a structural `Tag`:

```text
begin:   <|tool_call>call:{toolName}
content: JSONSchema(original request schema)
end:     <tool_call|>
```

This means ordinary text and Gemma4 reasoning remain free generation until the model emits `<|tool_call>`. Once that trigger is entered, xgrammar constrains the continuation to a request-visible function tag and the exact JSON Schema supplied for that tool. After a completed tag, free generation is available again and a later trigger can dispatch another call.

`required` and named choices keep the predecessor contract: a `TagsWithSeparator` tool sequence with `at_least_one=true`, `stop_after_first=false`, wrapped in a `Union` that permits either tools directly or `<|channel>thought\n ... <channel|>` followed by mandatory tools. No empty `ConstString("")` is introduced.

No parser code was changed.

## Upstream source authority

The implementation was checked against current upstream/nightly source rather than the 2026.3 release snapshot.

- OpenVINO GenAI `master`: `26144e25d8ac8945f55be6319728498e04e33530` (2026-09-07). `StructuredOutputConfig::TriggeredTags` is a first-class `StructuralTag`; the xgrammar backend compiles structural tags with `Grammar::FromStructuralTag`.
- OpenVINO Model Server upstream: `feba3c8983ac655203e0925599687a086194ca39` (2026-09-07). Existing Hermes3/Llama3/Phi4/Devstral generation builders already use `TriggeredTags` for conditional tool regions.
- xgrammar upstream inspected at `b5048784c65f70ca20bc5fb640b06c84583b7a92`. Its `triggered_tags` contract explicitly allows arbitrary text until a trigger and again after a tag. `at_least_one=true` disallows leading free text, so Gemma4 `auto` deliberately uses `false`.
- llama.cpp comparator inspected at `dbeb37548e25abc6e54961c4c99e63f191367809`. Current Gemma4 chat generation uses lazy grammar for non-required tool choice and the `<|tool_call>` grammar trigger.
- vLLM comparator inspected at `42801b3a6b3bb92397a04117449f4699b09db1df`. Its current Gemma4 engine parser intentionally avoids generic JSON structured-output enforcement for required/named because Gemma4 emits native `<|tool_call>call:...` syntax. OVMS does not copy that limitation because current OpenVINO/xgrammar can constrain the native tag syntax directly.

## llama.cpp semantics ported

1. `auto` does not eagerly force a tool call.
2. `<|tool_call>` is the conditional activation boundary.
3. After activation, only request-visible tool names are legal structural tags.
4. Arguments use the original per-tool JSON Schema rather than a reimplemented schema grammar.
5. Multiple tool triggers remain possible because `stop_after_first=false`.

## Differences from llama.cpp

llama.cpp represents this with PEG parsing plus `grammar_lazy` and `grammar_triggers`. OVMS uses OpenVINO GenAI's native `TriggeredTags`, which delegates the structural-tag grammar to xgrammar. No llama.cpp PEG code, sampler code, or parser code was copied.

Hard choices remain the existing OVMS eager compound grammar rather than being rewritten to llama.cpp internals.

## Tests written

`src/test/llm/generation_config/gemma4_generation_contract_test.cpp` now checks:

- `auto` produces `TriggeredTags` rather than an absent structured config;
- the trigger is exactly `<|tool_call>`;
- `auto.at_least_one == false`, preserving direct prose/no-tool answers;
- `auto.stop_after_first == false`;
- only request tools appear as tags;
- each tag preserves the exact request JSON Schema;
- nested objects, arrays, enum-capable schemas and nullable value types remain delegated unchanged to JSON Schema;
- `required` and named still use mandatory repeatable tool tags;
- hard choices still allow optional reasoning before mandatory tools;
- `none` and no-tool response-format behavior remains unchanged;
- active tools plus `response_format` still fail fast;
- unavailable named choices, invalid tool names and empty schemas fail;
- generated Gemma4 tool grammars contain no empty `ConstString("")`;
- the lazy auto structural config is passed through `validateStructuredOutputConfig` with the Gemma4 test tokenizer.

The first test commit was made before the implementation:

```text
bc4cd8c08749d861651aca278d50aa8dbb185789
    test(gemma4): specify auto guided-generation contract
```

At that commit the new auto expectations are source-level RED because the predecessor still executes `config.structured_output_config.reset()` for `auto`. No hosted workflow was triggered for that commit, so this is not reported as an executed failing test run.

## Static/unit verification performed here

```text
Branch re-resolution: PASS
  feature/gemma4-llamacpp-auto-generator-port started exactly at BASE_SHA
  predecessor fix/gemma4-google-template-session-state also resolved to BASE_SHA

Upstream API inspection: PASS
  TriggeredTags exists in current OpenVINO GenAI master
  TriggeredTags is accepted as StructuredOutputConfig::StructuralTag
  OpenVINO xgrammar backend compiles structural tags via Grammar::FromStructuralTag
  upstream OVMS already uses TriggeredTags in adjacent model builders

Diff/ancestry inspection before report: PASS
  branch ahead of BASE_SHA by 2 implementation/test commits
  behind_by=0
  merge base == BASE_SHA
  production changes limited to generation_config_builder.hpp
  test changes limited to gemma4_generation_contract_test.cpp
  parser changes: NONE

Hosted CI status for implementation commit: NO STATUS / NO WORKFLOW RUN
```

A local clone/build could not be performed in this session because the execution container had no DNS access to GitHub. This is an environment limitation, not a test result.

## NOT RUN

The following are deliberately **NOT RUN**, not PASS:

- Bazel compile of the modified C++ target;
- `//src/test/llm/generation_config:gemma4_generation_contract_test` execution;
- Windows OVMS build;
- OpenVINO GenAI/xgrammar runtime validation against the exact weekly/nightly binaries installed on the Arc host;
- Gemma4 26B-A4B live inference;
- streaming acceptance;
- chained tool-response continuation;
- multi-call live acceptance.

## Validation-failure behavior

Hard `required`/named choices retain the existing fail-closed wrapper contract: `unsetStructuredOutputConfig()` refuses to clear their grammar after validation failure.

`auto` retains the existing generic OVMS validation fallback: if the newly built `TriggeredTags` fails runtime validation, `OpenAIApiHandler` logs the validation failure and calls `unsetStructuredOutputConfig()`, allowing the request to continue without guided generation. This branch does not broaden scope by changing that generic policy. Treat an observed auto validation fallback as a failed acceptance signal, not as successful lazy enforcement.

## Local acceptance commands

First build the exact branch head with the same weekly/nightly OpenVINO + GenAI package set intended for deployment. Then run the focused generation contract target:

```text
bazel test //src/test/llm/generation_config:gemma4_generation_contract_test
```

Also run the existing Gemma4 parser contract target used by the predecessor acceptance to prove the untouched parser still passes in the rebuilt tree.

After the build, launch the same Gemma4 26B-A4B model/profile used by predecessor acceptance and execute the matrix below against `/v3/chat/completions`.

## Local agent acceptance matrix

### AUTO direct prose

```text
tool_choice=auto
tools=[get_disk_free]
user="Say hello."
```

Expected: ordinary assistant prose is legal; no tool call is mandatory.

### AUTO natural tool

```text
tool_choice=auto
tools=[get_disk_free]
user="Check free disk space on localhost."
```

Expected: a valid structured `get_disk_free` call. No unavailable function name.

### AUTO schema pressure

Tool:

```text
set_level(level enum ["low","medium","high"])
```

Use a prompt that pressures the model toward a value outside the enum.

Expected: if the model enters `<|tool_call>`, the emitted argument cannot leave the enum. A value outside the enum is a hard failure of the lazy constraint.

### AUTO reasoning -> normal response

Enable Gemma4 thinking and ask a question that should not need a tool.

Expected: reasoning may occur and the assistant may end in ordinary prose without any tool call.

### AUTO reasoning -> tool

Enable thinking and ask for disk space.

Expected: reasoning may precede `<|tool_call>`, after which function name and arguments are constrained.

### REQUIRED unnatural

```text
tool_choice=required
tools=[get_disk_free]
user="Say hello."
```

Expected: at least one tool call is mandatory.

### REQUIRED reasoning

Repeat the required case with thinking enabled.

Expected: optional reasoning followed by a mandatory tool call; prose-only EOS is not legal.

### NAMED

Provide two tools and select the second by named tool choice.

Expected: only the selected function can be generated, with its own JSON Schema.

### STREAM AUTO

Repeat AUTO natural tool with:

```text
stream=true
```

Expected: streaming parser emits a valid tool-call delta sequence and does not leak/break the trigger boundary.

### MULTI CALL

Use a request that naturally needs two calls.

Expected: multiple valid tool calls remain possible; `stop_after_first=false` must not collapse the response to one call.

### CHAINED

```text
assistant tool call
-> tool_response
-> assistant continuation
```

Expected: the continuation may answer normally or enter another constrained tool branch under `auto`.

### INVALID STRUCTURED CONFIG

Supply a schema known to fail xgrammar validation in the deployed nightly.

Expected:

- `required`/named: fail closed, never silently unconstrained;
- `auto`: current generic OVMS behavior may log and remove the structured config. Record this as an acceptance failure for lazy enforcement and preserve the log as evidence.

## Exact lazy status

```text
EXACT_LLAMA_CPP_LAZY_SEMANTICS: IMPLEMENTED
```

The semantic mechanism exists natively in the selected OpenVINO GenAI/xgrammar upstream: free generation before the trigger, constrained tag dispatch after the trigger, then free generation again. The remaining acceptance gap is build/runtime evidence on the target weekly/nightly OVMS + Intel Arc environment, not a missing generator primitive.

## Files changed by the implementation session

```text
src/llm/io_processing/generation_config_builder.hpp
src/test/llm/generation_config/gemma4_generation_contract_test.cpp
docs/gemma4-auto-generator-port-handoff.md
```

Parser changes: `NONE`.
