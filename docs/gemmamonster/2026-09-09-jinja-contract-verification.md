# Gemma4 Jinja contract verification

**Date:** 2026-09-09  
**Target branch:** `integration/gemma4-parser-generator-refit-next`  
**Baseline at start of this verification:** `7a8c5e0d6ca397b868f80e401dda9eb2dac7358c`

This note verifies the Gemma4 Jinja contract surface before adding a canonical rendered-prompt test. It records what comes from Google's current canonical template, what is intentionally different in the OVMS test fixture, and what the next conformance test is allowed to assert.

The outcome is not "replace the OVMS template with Google's template." The outcome is: keep the local compatibility fixture, but test the wire-semantics that must remain aligned with the current Google Gemma4 protocol.

## 1. Google canonical source

Canonical source inspected:

- Model repository: `google/gemma-4-31B-it`
- File: `chat_template.jinja`
- Hugging Face file commit shown for `chat_template.jinja`: `68abe48`
- Current visible commit title: `fix: chat template — null handling, reasoning preservation, turn-tag balance, input validation (#118)`
- File size shown: `18.7 kB`
- Template header: `Template: Google Gemma 4 Canonical Chat Template`
- Template header date: `Published: 2026-07-09`

Important canonical semantics visible in the inspected Google template:

1. The function declaration includes an optional `response` schema block when `tool_data['function']['response']` is present.
2. `format_argument()` handles `none` explicitly as native `null` before string/boolean/mapping/sequence branches.
3. Setup initializes `prev_non_tool_role`, `enable_thinking | default(false)`, and `preserve_thinking | default(false)`.
4. Assistant tool calls serialize as native Gemma4 wire format: `<|tool_call>call:<name>{...}<tool_call|>`.
5. `tool_calls[].function.arguments` must be a mapping/object or `none`; any other type raises a template exception instructing the caller to deserialize arguments before rendering.
6. Reasoning uses `<|channel>thought\n...\n<channel|>` and `preserve_thinking` can keep reasoning when an assistant message also has tool calls.
7. Tool responses serialize as `<|tool_response>response:<name>{...}<tool_response|>`.
8. When `add_generation_prompt` follows a tool response with thinking enabled, the template emits an open thought channel: `<|channel>thought\n`.

These are the canonical wire-semantics for the Jinja conformance gate.

## 2. Local OVMS fixture source

Local fixture inspected:

- Repository: `DassaultFalconKing/model_server`
- Branch: `integration/gemma4-parser-generator-refit-next`
- File: `src/test/llm/chat_templates/chat_template_gemma.jinja`
- Current blob SHA during inspection: `55f02f1a445bfd75b33aa78408595a846fe45df8`

The local fixture is not a byte-identical copy of the current Google template. It is an OVMS compatibility fixture.

The file header explicitly records a local modification:

- ignore the `response` field from tool definitions because it was broken for the local serving path and is inline with other servings.

Local behavior currently observed:

1. Tool declarations intentionally omit Google's optional `response` schema block.
2. `format_argument()` supports strings, booleans, mappings, sequences, and a final raw fallback, but does not contain Google's explicit `none -> null` branch.
3. Assistant tool calls serialize to the same native Gemma4 wire shape: `<|tool_call>call:<name>{...}<tool_call|>`.
4. Unlike the current Google template, local `function['arguments']` still accepts a string fallback and writes it directly.
5. Local OpenAI tool-response replay forward-scans consecutive `role: tool` messages and resolves `tool_call_id` back to the assistant call name.
6. Local continuation detection uses a backward scan over previous non-tool messages rather than Google's newer tracked `prev_non_tool_role` state.
7. Local `add_generation_prompt` does not include Google's explicit `tool_response + enable_thinking -> open thought channel` branch.

This means local tests must not pretend the fixture is Google canonical. The correct model is split authority:

- Google template is the canonical protocol oracle.
- Local fixture is the OVMS compatibility oracle.
- Conformance tests compare the wire-significant behavior, not every line of template implementation.

## 3. Git history / changes-made evidence for local fixture

GitHub path history for `src/test/llm/chat_templates/chat_template_gemma.jinja` shows at least these relevant commits on the target lineage:

### `11ae15ac1eecf03e47812156a96836937daecc0c`

Commit message:

`Auto parser detect / auto input-workaround detection / --parser none (#4312)`

Relevant changes from this commit class:

- introduced auto parser detection / auto input-workaround detection;
- documented that VLM pipelines switch to JINJA by default for broader chat template support;
- added `chat_template_end_to_end_jinja_test.cpp` to Python-enabled tests;
- added the `test_chat_template_workarounds` target surface.

This establishes that OVMS local Jinja testing is not a mock-only surface; the project already has a production-style Jinja rendering path wired into tests.

### `270e6029dde097ddce8116ff114de0ea3c242a5a`

Commit message:

`from_json no longer needed in gemma templates (#4365)`

Relevant changes in `src/test/llm/chat_templates/chat_template_gemma.jinja`:

- added the file-header note that the local template ignores `response` from tool definitions;
- removed the `response` schema rendering block from the local test fixture;
- changed tool-call argument handling away from `from_json` and toward direct `function['arguments'] is mapping` handling;
- preserved local fixture compatibility rather than vendoring the exact upstream Google template.

This is the concrete reason the local fixture must be treated as a compatibility fixture, not as a byte-for-byte Google fixture.

## 4. Contract decision

The Jinja conformance gate should assert these shared canonical wire properties:

- Gemma4 parser detection from `<|tool_call>call:`;
- Gemma4 reasoning parser detection from thought-channel markers;
- tool-call rendering shape: `<|tool_call>call:<name>{...}<tool_call|>`;
- native object arguments with recursive strings, booleans, arrays, objects, and `null` in the canonical oracle;
- tool-response replay shape: `<|tool_response>response:<name>{...}<tool_response|>`;
- reasoning replay shape: `<|channel>thought\n...\n<channel|>`;
- post-tool continuation with an open thought channel when canonical Google semantics require it;
- local compatibility fixture remains allowed to accept string `function.arguments` because OVMS adapter tests already cover conversion of OpenAI string arguments to object arguments.

The Jinja conformance gate must not assert byte-identical equality between the local fixture and the Google template.

## 5. Next implementation shape

Add a focused conformance test instead of copying the full 18.7 kB Google template into this repository.

Recommended target:

`src/test/llm/gemma4_overlay/gemma4_google_jinja_contract_test.cpp`

Recommended test roles:

1. A compact canonical-Google semantic snippet, annotated with `google/gemma-4-31B-it chat_template.jinja @ 68abe48`, should verify:
   - `none -> null`;
   - object-only tool arguments;
   - `raise_exception` on string tool arguments;
   - post-tool open-thought continuation.
2. Existing local fixture tests should continue verifying OVMS compatibility behavior, especially string-argument adapter conversion.
3. The protocol runner should treat canonical-Google conformance and OVMS-compatibility conformance as separate gates.

## 6. Do-not-overwrite rule

Do not replace `src/test/llm/chat_templates/chat_template_gemma.jinja` with the current Google template unless a separate runtime decision is made to abandon the compatibility fixture. Such a replacement would reintroduce semantics that were intentionally removed by `270e6029...`, especially direct `response` schema rendering, and would also change the current string-argument compatibility behavior.

The next code step is therefore not "sync template." It is "add a canonical semantic oracle and compare it against the local compatibility path."
