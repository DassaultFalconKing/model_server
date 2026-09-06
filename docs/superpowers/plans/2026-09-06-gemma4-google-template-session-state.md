# Gemma4 Google-template Session State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible Gemma4 serving line that uses the current official Google chat template, persists one session seed plus exact request/config evidence across turns, and safely recovers known bare `call:tool{...}` emissions.

**Architecture:** Add a small generic disk-backed `SessionStateStore` at the `GenAiServable::parseRequest()` boundary. It mutates only the per-request JSON document by resolving/injecting a session seed before the existing OpenAI parser/builders run, then records the resulting effective generation config. Deployment tooling creates a model overlay from Wondernutts IR while replacing only `chat_template.jinja` with a Google-resolved template and recording provenance. Gemma4 bare-call recovery remains parser-local and guarded by the request tool registry.

**Tech Stack:** C++17, RapidJSON, std::filesystem/std::mutex/std::list, Bazel/gtest, PowerShell 7+, Hugging Face HTTP API, OpenVINO GenAI.

**Spec:** `docs/superpowers/specs/2026-09-06-gemma4-google-template-session-state-design.md`

## Global Constraints

- Implementation branch: `fix/gemma4-google-template-session-state`.
- Exact predecessor: `7300995129f5686fe7ec6999905031399698745e`.
- Do not modify `main` or `fix/gemma4-final-toolcalling-review`.
- Wondernutts supplies only IR/weights; its `chat_template.jinja` is never copied into the runtime overlay.
- Google template is resolved latest-at-preparation-time and then pinned by exact resolved revision + SHA256 in provenance.
- `TriggeredTags` is out of scope.
- Session behavior is opt-in via `X-OVMS-Session-ID`.
- Requests without a session header must preserve legacy OpenAI behavior.
- One session seed is immutable for the lifetime of a session ID.
- Full turn payloads live on disk; only bounded manifest state is cached in RAM.
- Store writes are atomic and storage growth is bounded.
- Bare-call recovery may execute only names present in the current request tool registry.
- Existing exact tool-result SHA propagation must remain green.

---

### Task 1: Session store core

**Files:**
- Create: `src/llm/session_state_store.hpp`
- Create: `src/llm/session_state_store.cpp`
- Create: `src/test/llm/session_state_store_test.cpp`
- Modify: `src/llm/BUILD`
- Modify: `BUILD` test aggregation if required by the existing test-library pattern.

**Interfaces:**
- Consumes: `rapidjson::Document` request JSON and optional `model` string.
- Produces:
  - `SessionStateStore::fromEnvironment()`
  - `SessionTurnContext SessionStateStore::beginTurn(const std::string& sessionId, const std::string& rawBody, rapidjson::Document& effectiveDocument)`
  - `void SessionStateStore::recordGenerationConfig(const SessionTurnContext&, const ov::genai::GenerationConfig&, const std::string& toolChoice)`
  - `bool SessionStateStore::enabled() const`

- [ ] **Step 1: Write failing store tests**

Add gtests covering:

```cpp
TEST(SessionStateStoreTest, FirstTurnWithoutSeedGeneratesAndPersistsNonZeroSeed);
TEST(SessionStateStoreTest, ExplicitFirstSeedBecomesSessionSeed);
TEST(SessionStateStoreTest, LaterTurnWithoutSeedReusesPersistedSeed);
TEST(SessionStateStoreTest, DifferentExplicitSeedReturnsConflict);
TEST(SessionStateStoreTest, ReloadsManifestAfterNewStoreInstance);
TEST(SessionStateStoreTest, EvictsRamEntryWithoutDeletingDiskState);
TEST(SessionStateStoreTest, RejectsUnsafeSessionId);
TEST(SessionStateStoreTest, RefusesWritePastByteQuota);
```

Each test uses a unique temporary directory and a small synthetic RapidJSON chat request.

- [ ] **Step 2: Run RED**

Run:

```text
bazel test //src/test:ovms_tests --test_filter=SessionStateStoreTest.*
```

Expected: FAIL because `SessionStateStore` does not exist.

- [ ] **Step 3: Implement minimal store**

Implement:

```cpp
struct SessionTurnContext {
    bool active = false;
    std::string sessionId;
    uint64_t turnIndex = 0;
    uint32_t seed = 0;
};

class SessionStateStore {
public:
    static std::shared_ptr<SessionStateStore> fromEnvironment();
    bool enabled() const;
    absl::StatusOr<SessionTurnContext> beginTurn(
        const std::string& sessionId,
        const std::string& rawBody,
        rapidjson::Document& effectiveDocument);
    absl::Status recordGenerationConfig(
        const SessionTurnContext& turn,
        const ov::genai::GenerationConfig& config,
        const std::string& toolChoice);
};
```

Use:

- `std::filesystem` for directories/files;
- `std::mutex` around cache and durable-index accounting;
- `std::list<std::string>` + unordered map for LRU;
- atomic same-directory temp write then rename;
- strict session-id validation;
- request body size check before journaling;
- a cached approximate/current byte count initialized by scanning the store root once.

Seed injection must add or replace a top-level numeric `seed` member in `effectiveDocument` using that document allocator.

- [ ] **Step 4: Run GREEN**

Run the same filtered test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/llm/session_state_store.* src/test/llm/session_state_store_test.cpp src/llm/BUILD BUILD
git commit -m "feat(llm): add persistent session seed store"
```

---

### Task 2: Integrate session resolution into GenAiServable request lifecycle

**Files:**
- Modify: `src/llm/servable.hpp`
- Modify: `src/llm/servable.cpp`
- Modify: `src/llm/servable_initializer.cpp` only if store construction belongs in properties initialization.
- Modify/Create test: `src/test/llm/session_state_integration_test.cpp`
- Modify Bazel test deps.

**Interfaces:**
- `GenAiServableProperties` gains `std::shared_ptr<SessionStateStore> sessionStateStore`.
- `GenAiServableExecutionContext` gains `SessionTurnContext sessionTurn`.

- [ ] **Step 1: Write failing integration tests**

Cover:

```cpp
TEST(SessionStateIntegrationTest, SessionSeedIsInjectedBeforeOpenAIRequestParsing);
TEST(SessionStateIntegrationTest, SameSessionProducesSameEffectiveRngSeedAcrossTurns);
TEST(SessionStateIntegrationTest, RequestWithoutSessionHeaderKeepsLegacySeedBehavior);
TEST(SessionStateIntegrationTest, ConflictingSeedFailsBeforeGenerationStarts);
```

Use a real `GenerationConfigBuilder` path where practical; otherwise assert that the post-session request document contains the exact seed that `OpenAIApiHandler` will parse.

- [ ] **Step 2: Run RED**

Expected: FAIL because request lifecycle ignores session headers.

- [ ] **Step 3: Implement header/session integration**

Add a case-insensitive helper for `X-OVMS-Session-ID`.

In `GenAiServable::parseRequest()` before constructing `OpenAIChatCompletionsHandler` / `OpenAIResponsesHandler`:

1. if no session header, do nothing;
2. if store disabled, preserve legacy behavior and log one warning;
3. otherwise call `beginTurn()` with the original `payload.body` and mutable parsed document;
4. store returned `SessionTurnContext` in execution context;
5. on error, return the status before handler construction.

After `extractInputRequest(configBuilder)` succeeds, call `recordGenerationConfig()` with the exact effective config and handler tool choice.

- [ ] **Step 4: Run GREEN**

Run session store + integration tests. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/llm/servable.* src/llm/servable_initializer.cpp src/test/llm/session_state_integration_test.cpp src/llm/BUILD BUILD
git commit -m "feat(llm): persist effective multi-turn session config"
```

---

### Task 3: Safe Gemma4 bare `call:` recovery

**Files:**
- Modify: `src/llm/io_processing/gemma4/gemma4_tool_parser.cpp`
- Modify: `src/llm/io_processing/gemma4/gemma4_tool_parser.hpp` only if helper declarations are needed.
- Modify: `src/test/llm/output_parsers/gemma4_output_parser_test.cpp`
- Modify: `src/test/llm/output_parsers/gemma4_v2_contract_test.cpp` if contract vectors belong there.

**Interfaces:**
- Existing `Gemma4ToolParser` API remains unchanged.
- New parser-local helper may locate a guarded bare-call candidate from the current streaming position.

- [ ] **Step 1: Add failing positive and negative tests**

Positive observed shape:

```text
call:inspect_repository_state{repository:<|"|>C:\\git\\repo<|"|>,ref:<|"|>abc<|"|>}
```

Also test newline/whitespace-prefixed bare call after reasoning content.

Negative cases:

```text
Documentation example: call:inspect_repository_state{...}
The token call:unknown_tool{x:1} is shown here.
"call:inspect_repository_state{x:1}"
call:inspect_repository_state{x:[1,2}
```

Assertions:

- known bare call at an allowed boundary becomes exactly one ToolCall delta;
- unknown tool remains content;
- quoted/prose examples remain content;
- malformed container does not become executable.

- [ ] **Step 2: Run RED**

Run Gemma4 parser tests. Expected: at least the positive late-bare-call case FAILS under current exact-phase-entry logic.

- [ ] **Step 3: Implement guarded recovery**

When canonical `<|tool_call>` is absent, search forward for `call:` candidates only at safe lexical boundaries. For each candidate:

1. parse/normalize tool name;
2. require `toolNameSchemaMap.contains(name)`;
3. require `{` or `(` argument opener after optional whitespace;
4. reuse existing matching-container and native-argument parsing;
5. promote only the first fully valid candidate;
6. preserve preceding text as ordinary content before switching parser state.

Canonical tagged calls keep priority.

- [ ] **Step 4: Run GREEN + full Gemma parser corpus**

Run all Gemma4 output parser tests including tokenizer-backed fixture tests. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/llm/io_processing/gemma4/gemma4_tool_parser.* src/test/llm/output_parsers/gemma4*_test.cpp
git commit -m "fix(gemma4): recover guarded bare tool calls"
```

---

### Task 4: Google-template runtime overlay + provenance

**Files:**
- Create: `scripts/gemma4/prepare-google-template-overlay.ps1`
- Create: `scripts/gemma4/collect-runtime-provenance.ps1`
- Create: `docs/gemma4/GOOGLE-TEMPLATE-RUNTIME.md`

**Interfaces:**

`prepare-google-template-overlay.ps1` parameters:

```powershell
param(
  [Parameter(Mandatory=$true)][string]$SourceModelPath,
  [Parameter(Mandatory=$true)][string]$OverlayPath,
  [string]$GoogleModel = 'google/gemma-4-26B-A4B-it',
  [string]$GoogleRevision = '',
  [switch]$Force
)
```

- [ ] **Step 1: Add script self-check/dry-run contract**

The script must fail if:

- source model is missing required IR files;
- resolved source is not the configured Google model;
- downloaded template is empty or lacks Gemma4 native markers such as `<|tool_call>call:` and `<|tool_response>`;
- overlay path equals source path.

- [ ] **Step 2: Implement overlay preparation**

Behavior:

1. resolve Google latest revision via HF model API when `-GoogleRevision` is empty;
2. fetch `chat_template.jinja` from that exact revision;
3. create overlay without mutating source;
4. link/copy source model files except Wondernutts `chat_template.jinja`;
5. write downloaded Google template as overlay `chat_template.jinja`;
6. write `gemma4-template-provenance.json` with resolved revision, SHA256 and paths.

On Windows prefer hardlinks for large immutable model files when same-volume; fall back to copy for small metadata and when hardlink creation is unavailable. Never overwrite source.

- [ ] **Step 3: Implement runtime provenance collector**

Record JSON containing:

- timestamp;
- OVMS path/version/file hash;
- `OpenVINO_DIR`;
- OpenVINO version if discoverable;
- GenAI version if discoverable;
- hashes for `openvino*.dll` and `openvino_genai*.dll` under the selected runtime directories;
- current Git HEAD when invoked from a checkout.

- [ ] **Step 4: Document exact launch contract**

Document that acceptance launches OVMS against the overlay path, not the Wondernutts source path.

- [ ] **Step 5: Commit**

```bash
git add scripts/gemma4 docs/gemma4/GOOGLE-TEMPLATE-RUNTIME.md
git commit -m "feat(gemma4): prepare google-template runtime overlay"
```

---

### Task 5: Extend live chain harness for persistent sessions and sampling evidence

**Files:**
- Modify: `ab-evidence/live_chain_harness.py`
- Create/modify: `docs/gemma4/local-agent-grounded-facts-test-handoff.md`

**Interfaces:**

New harness options:

```text
--session-id
--seed
--temperature
--top-p
--top-k
--persist-request-metadata
```

- [ ] **Step 1: Write harness-level tests or self-testable pure helpers**

Extract helpers that construct request headers/payloads and assert:

- every turn uses the same `X-OVMS-Session-ID`;
- explicit seed is either present on all turns or omitted deliberately to test server injection;
- exact request JSON is persisted before sending;
- response/raw evidence stays associated with the exact turn index.

- [ ] **Step 2: Implement session-aware harness**

For one chain, generate or accept one stable session ID and reuse it for every turn. Save a `session-config.json` containing requested sampling profile and session id.

Do not silently change temperature/top-p/top-k during a chain.

- [ ] **Step 3: Add restart/reload mode**

Add a mode/instruction that can execute turn 1, stop, then later execute turn 2 with the same session ID so local acceptance can prove disk reload after OVMS restart.

- [ ] **Step 4: Commit**

```bash
git add ab-evidence/live_chain_harness.py docs/gemma4/local-agent-grounded-facts-test-handoff.md
git commit -m "test(gemma4): persist session and sampling evidence"
```

---

### Task 6: Verification and local Windows acceptance handoff

**Files:**
- Create: `docs/gemma4/NEWEST-RUNTIME-LOCAL-ACCEPTANCE.md`

- [ ] **Step 1: Run source/build contract tests**

At minimum:

```text
windows_build_fast.ps1 -Mode Verify -WithPython $true
```

with the required tokenizer fixture path when the parser contract needs it.

- [ ] **Step 2: Verify runtime/template provenance**

Prepare a fresh Google-template overlay and collect runtime provenance. Confirm Wondernutts source tree is unchanged before/after.

- [ ] **Step 3: Session persistence smoke**

Run two turns with the same session ID, restart OVMS between turns, and prove the exact same effective seed from journal evidence.

- [ ] **Step 4: Parser smoke**

Run canonical tool call and a controlled bare `call:known_tool{...}` fixture; confirm both produce structured tool calls and negative prose remains text.

- [ ] **Step 5: Full chained campaign**

Run named/required/auto campaigns with persisted raw/effective requests and stable session seeds. Report action selection separately from parser recognition and grounded-value fidelity.

- [ ] **Step 6: Final report**

Return exact:

```text
BRANCH:
HEAD:
BASE:
OVMS_BINARY_SHA256:
OPENVINO_VERSION:
GENAI_VERSION:
GOOGLE_TEMPLATE_MODEL:
GOOGLE_TEMPLATE_REVISION:
GOOGLE_TEMPLATE_SHA256:
SESSION_STORE:
SESSION_RELOAD:
BARE_CALL_RECOVERY:
PARSER_CORPUS:
NAMED_CHAIN:
REQUIRED_CHAIN:
AUTO_CHAIN:
GROUNDED_VALUE_FIDELITY:
OVERALL:
```

Do not promote the branch if runtime provenance is missing or the model was launched against the Wondernutts template.