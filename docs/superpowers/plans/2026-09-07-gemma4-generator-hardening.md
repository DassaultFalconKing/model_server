# Gemma4 Generator Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the remaining generator-side Gemma4 tool-calling work by localizing Gemma4 fail-closed behavior, honoring OpenAI `parallel_tool_calls`, and preparing a reproducible runtime acceptance gate without changing parser behavior.

**Architecture:** Keep OpenAI request parsing generic and carry `parallel_tool_calls` as request state. Keep model-specific validation fallback policy inside `Gemma4GenerationConfigBuilder`. Map parallel-call policy directly onto OpenVINO GenAI/xgrammar structural-tag controls: repeatable tags when true, stop after the first tag when false.

**Tech Stack:** C++17, OpenVINO Model Server, OpenVINO GenAI `StructuredOutputConfig`, xgrammar, RapidJSON, GoogleTest, Bazel.

**Spec:** `docs/gemma4-auto-generator-port-handoff.md`

## Global Constraints

- Work only on `feature/gemma4-llamacpp-auto-generator-port` or a child branch if the shared branch moves.
- Do not move `main` or `fix/gemma4-google-template-session-state`.
- Do not change Gemma4 parser code unless a generator test demonstrates a parser defect.
- Preserve existing `none`, `auto`, `required`, named-choice, response-format, reasoning and schema behavior.
- `parallel_tool_calls` defaults to `true`.
- Non-boolean `parallel_tool_calls` is an invalid request.
- `parallel_tool_calls=false` permits at most one generated tool call in the assistant turn.
- Hard Gemma4 choices remain fail-closed if structured-output validation fails; other builders retain their old fallback behavior.

---

### Task 1: Localize hard-choice validation fallback to Gemma4

**Files:**
- Modify: `src/llm/io_processing/base_generation_config_builder.hpp`
- Modify: `src/llm/io_processing/generation_config_builder.hpp`
- Test: `src/test/llm/generation_config/gemma4_generation_contract_test.cpp`

**Interfaces:**
- Produces: `BaseGenerationConfigBuilder::shouldPreserveStructuredOutputOnValidationFailure() const`, default `false`.
- Produces: Gemma4 override backed by parsed hard-choice state.

- [ ] **Step 1: Write the failing regression test**

```cpp
TEST(Gemma4GenerationContractTest, ValidationFallbackPolicyIsGemmaSpecific) {
    auto request = requestWithTools("required");

    GenerationConfigBuilder gemma({}, "gemma4", false, STANDARD);
    gemma.parseConfigFromRequest(request);
    ASSERT_TRUE(gemma.getConfig().structured_output_config.has_value());
    gemma.unsetStructuredOutputConfig();
    EXPECT_TRUE(gemma.getConfig().structured_output_config.has_value());

    GenerationConfigBuilder hermes({}, "hermes3", false, STANDARD);
    hermes.parseConfigFromRequest(request);
    ASSERT_TRUE(hermes.getConfig().structured_output_config.has_value());
    hermes.unsetStructuredOutputConfig();
    EXPECT_FALSE(hermes.getConfig().structured_output_config.has_value());
}
```

- [ ] **Step 2: Run the focused test**

```bash
bazel test //src/test/llm/generation_config:gemma4_generation_contract_test --test_filter=Gemma4GenerationContractTest.ValidationFallbackPolicyIsGemmaSpecific
```

Expected before implementation: FAIL because the generic wrapper preserves structured output for every model when `tool_choice=required`.

- [ ] **Step 3: Implement the policy hook**

Base builder:

```cpp
virtual bool shouldPreserveStructuredOutputOnValidationFailure() const { return false; }
```

Gemma4 builder:

```cpp
bool hardToolChoice{false};

bool shouldPreserveStructuredOutputOnValidationFailure() const override {
    return hardToolChoice;
}
```

Set `hardToolChoice = isHardToolChoiceImpl(request.toolChoice)` at the start of Gemma4 request parsing. Remove the generic wrapper's `hardToolChoice` field and make `unsetStructuredOutputConfig()` consult the selected builder's policy.

- [ ] **Step 4: Run the focused generation-config target**

```bash
bazel test //src/test/llm/generation_config:gemma4_generation_contract_test
```

- [ ] **Step 5: Commit**

```bash
git commit -am "fix(gemma4): localize hard-choice validation policy"
```

---

### Task 2: Parse and carry `parallel_tool_calls`

**Files:**
- Modify: `src/llm/apis/openai_request.hpp`
- Modify: `src/llm/apis/openai_api_handler.cpp`
- Test: smallest OpenAI API parsing target that can inspect `getRequest()`.

**Interfaces:**
- Produces: `OpenAIRequest::parallelToolCalls`, type `bool`, default `true`.

- [ ] **Step 1: Add RED parsing cases**

Required behavior:

```text
field absent                  -> true
"parallel_tool_calls": true  -> true
"parallel_tool_calls": false -> false
"parallel_tool_calls": 1     -> InvalidArgument
"parallel_tool_calls": "no"  -> InvalidArgument
```

- [ ] **Step 2: Implement parsing in `parseTools()`**

```cpp
auto parallelToolCallsIt = doc.FindMember("parallel_tool_calls");
if (parallelToolCallsIt != doc.MemberEnd() && !parallelToolCallsIt->value.IsNull()) {
    if (!parallelToolCallsIt->value.IsBool())
        return absl::InvalidArgumentError("parallel_tool_calls is not a bool");
    request.parallelToolCalls = parallelToolCallsIt->value.GetBool();
}
```

- [ ] **Step 3: Run the API parsing tests**

Use the repository's existing HTTP/OpenAI handler test target containing `HttpOpenAIHandlerParsingTest`.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(openai): parse parallel tool call policy"
```

---

### Task 3: Enforce one-call vs repeatable-call generation in Gemma4

**Files:**
- Modify: `src/llm/io_processing/generation_config_builder.hpp`
- Test: `src/test/llm/generation_config/gemma4_generation_contract_test.cpp`

**Interfaces:**
- `buildAutoToolGrammar(tags, parallelToolCalls)` sets `TriggeredTags::stop_after_first = !parallelToolCalls`.
- `buildMandatoryToolGrammar(tags, parallelToolCalls)` sets `TagsWithSeparator::stop_after_first = !parallelToolCalls`.

- [ ] **Step 1: Write RED contract tests**

For `auto`, `required`, and named choice, assert:

```cpp
request.parallelToolCalls = true;  // stop_after_first == false
request.parallelToolCalls = false; // stop_after_first == true
```

For hard choices assert both branches of the reasoning union use the same stop policy.

- [ ] **Step 2: Implement the minimal wiring**

```cpp
triggeredTags->stop_after_first = !parallelToolCalls;
requiredTags->stop_after_first = !parallelToolCalls;
```

Pass `request.parallelToolCalls` from `parseConfigFromRequest()` into both grammar builders.

- [ ] **Step 3: Run all Gemma4 generation-contract tests**

```bash
bazel test //src/test/llm/generation_config:gemma4_generation_contract_test
```

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(gemma4): enforce parallel tool call policy"
```

---

### Task 4: Runtime acceptance and performance evidence

**Files:**
- Modify: `docs/gemma4-auto-generator-port-handoff.md`
- Create: `docs/gemma4-generator-runtime-acceptance.md` if a separate operator checklist is clearer.

- [ ] **Step 1: Define exact live cases**

```text
AUTO + parallel=true: two independent requested tools may both be emitted
AUTO + parallel=false: at most one tool call
REQUIRED + parallel=true: one or more calls, no prose-only completion
REQUIRED + parallel=false: exactly one call
NAMED + parallel=false: exactly one call and only the selected name
STREAM + parallel=false: no second tool-call delta
CHAINED tool_response: same policy on the next assistant turn
```

- [ ] **Step 2: Capture performance evidence**

Record TTFT and GenAI grammar compiler initialization time for a stable OpenCode toolbox. Do not add a grammar cache unless compiler time is materially visible in TTFT.

- [ ] **Step 3: Run source/CI verification available in the environment**

At minimum:

```bash
bazel test //src/test/llm/generation_config:gemma4_generation_contract_test
```

and the OpenAI API parsing target changed by Task 2. If Windows/nightly binaries are unavailable, report those runtime gates as NOT RUN rather than PASS.

- [ ] **Step 4: Final scope review**

Confirm parser files are unchanged, `main` and predecessor refs are unchanged, and the feature branch is a strict descendant of its previous head.
