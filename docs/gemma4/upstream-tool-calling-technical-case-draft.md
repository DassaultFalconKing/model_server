# Gemma4 Tool Calling in OVMS: Upstream Technical Case

> **Status:** draft for upstream review preparation  
> **Repository:** `DassaultFalconKing/model_server`  
> **Working branch:** `feature/gemma4-llamacpp-auto-generator-port`  
> **Accepted runtime evidence:** `fea1a5f1c2640aa60fe6a840d3f62b38fb7b7767`  
> **Lazy-auto implementation point:** `80b885281443d7b0fd5f3a2f71237a8524d69b04`  
> **Important:** the working branch has continued beyond `80b885`; later generator hardening, including `parallel_tool_calls`, must not borrow the earlier runtime acceptance.

This document consolidates the three previously separate analysis blocks into one upstream-facing Markdown draft:

1. architecture and provenance;
2. Generator and Parser evidence matrices;
3. maintainer case, failure ownership and acceptance obligations.

The core rule of this report is simple:

> **No claim is stronger than the exact commit and runtime evidence that supports it.**

---

## 1. Executive summary

Gemma4 tool calling in OVMS has two distinct model-specific responsibilities:

- **Generator:** translates OpenAI request semantics such as `tool_choice`, request-visible tools and JSON Schemas into OpenVINO GenAI structured-generation policy;
- **Parser:** reconstructs Gemma4 native tool-call output into OpenAI-compatible tool-call objects while preserving execution safety.

Many failures that superficially look like parser failures originate earlier. A parser can normalize a call that the model emitted; it cannot recover a tool call that generation never emitted, force a required call after prose-only EOS, or repair a named-tool violation without inventing behavior.

The design therefore follows two complementary rules:

> **Canonical Generator. Tolerant but execution-strict Parser.**

The Parser hardening is already backed by an accepted runtime line. The newer lazy `tool_choice=auto` Generator is architecturally strong and contract-specified, but its exact implementation point must receive its own target-runtime acceptance before inheriting any 100/100 claim.

---

## 2. Authority and evidence hierarchy

The implementation is evaluated against the following authority order:

1. **Google canonical Gemma4 protocol and chat template**;
2. **OpenAI API semantics exposed by OVMS**;
3. **OpenVINO GenAI and xgrammar structured-generation capabilities**;
4. **independent runtime implementations such as llama.cpp and vLLM as compatibility evidence**;
5. **fork contracts, source diffs and exact runtime evidence**.

llama.cpp and vLLM are not treated as Gemma4 specifications. They are useful because independently developed systems encounter the same protocol and streaming problems.

The lazy Generator handoff pins the upstream versions used for the architectural comparison:

| Component | Pinned source | Relevance |
|---|---|---|
| OpenVINO GenAI | `26144e25d8ac8945f55be6319728498e04e33530` | `StructuredOutputConfig::TriggeredTags` is a first-class structural-tag mode and is compiled through the xgrammar backend. |
| upstream OVMS | `feba3c8983ac655203e0925599687a086194ca39` | Hermes3, Llama3, Phi4 and Devstral builders already use `TriggeredTags`. |
| xgrammar | `b5048784c65f70ca20bc5fb640b06c84583b7a92` | Triggered tags permit free generation before a trigger and after a completed tag; `at_least_one=true` removes the leading-free-text property. |
| llama.cpp | `dbeb37548e25abc6e54961c4c99e63f191367809` | Gemma4 non-required tool choice uses lazy grammar around the native `<|tool_call>` boundary. |
| vLLM | `42801b3a6b3bb92397a04117449f4699b09db1df` | Dedicated Gemma4 parser handles native call syntax, custom strings, recursive values and streaming partials. |

See also [`docs/gemma4-auto-generator-port-handoff.md`](../gemma4-auto-generator-port-handoff.md).

---

## 3. Native Gemma4 protocol boundary

The relevant native call envelope is:

```text
<|tool_call>call:<tool-name>{<native Gemma4 arguments>}<tool_call|>
```

Gemma4 native argument syntax is recursively structured and may contain custom string delimiters such as:

```text
<|"|>value<|"|>
```

The assistant response itself is not a JSON document. A legal turn can contain reasoning, normal text and one or more native tool-call regions.

Conceptually:

```text
optional reasoning
        ↓
optional ordinary assistant content
        ↓
optional native tool call
        ↓
<|tool_call>call:function_name{...}<tool_call|>
```

This is the reason generic whole-response JSON-schema enforcement is the wrong abstraction for `tool_choice=auto`.

---

# Part I — Generator

## 4. Generator responsibility

The Generator owns the policy before and during decoding:

```text
OpenAI request
    ↓
tool_choice + tools + schemas
    ↓
Gemma4GenerationConfigBuilder
    ↓
OpenVINO GenAI StructuredOutputConfig
    ↓
xgrammar
    ↓
model generation
```

The Generator does **not** parse completed model output. Its job is to map caller intent into legal generation paths.

The first accepted contract-driven generation policy distinguished:

```text
tool_choice=none or no tools
    -> no tool constraint

tool_choice=auto
    -> native Gemma4 generation, globally unconstrained

tool_choice=required
    -> mandatory native Gemma4 structural grammar

tool_choice=<named tool>
    -> mandatory native grammar restricted to the selected tool
```

Representative history includes:

- `5950ecce2d900af13fc318a525c0dd5087736033` — define auto and hard-choice generation contracts;
- `422627c4e9b690d6ba59b98dd17956be5b0083ad` — add native-auto and hard-choice generation policy;
- `ec45bdd7ac62710c2c98e83d0cabe6febbedeeca` — hard choice cannot fall back to unconstrained generation;
- `6847c687143d367e79733dd74ae249b45d96ded6` — keep hard choices fail-closed on validation fallback.

The accepted runtime line later reached exact SHA:

```text
fea1a5f1c2640aa60fe6a840d3f62b38fb7b7767
```

That accepted evidence is intentionally not transferred to later Generator revisions.

---

## 5. Why generic JSON structured output is insufficient

The tempting simplification is:

> Tools have JSON Schemas, so constrain the whole assistant response as JSON.

That would be incorrect for Gemma4 because only the **argument content** has JSON-schema semantics. The surrounding assistant protocol is model-specific.

A global JSON grammar from generation position zero would incorrectly restrict:

- reasoning before deciding whether a tool is needed;
- normal prose when `auto` chooses not to call;
- native `<|tool_call>` framing;
- free generation after a completed tool region;
- later tool triggers in the same turn when parallel calls are permitted.

The correct separation is:

```text
assistant protocol framing
    -> Gemma4-specific generation policy

argument content
    -> original request JSON Schema
```

The grammar should therefore answer the narrow question:

> Once the model enters a native Gemma4 tool region, what continuations are legal?

not the broader and incorrect question:

> Must the entire assistant response be a JSON object?

---

## 6. Second-generation lazy `auto`

The dedicated lazy-auto implementation point is:

```text
80b885281443d7b0fd5f3a2f71237a8524d69b04
fix(gemma4): port lazy-capable auto tool generation
```

It introduces an explicit three-way policy:

```text
Disabled
    -> no tool grammar

Auto
    -> lazy / triggered tool grammar

Hard
    -> eager mandatory grammar
```

For `auto`, the builder creates:

```text
StructuredOutputConfig::TriggeredTags

trigger:          <|tool_call>
at_least_one:     false
stop_after_first: false   # at the 80b885 implementation point
```

Each request-visible tool is represented as a structural tag:

```text
begin:   <|tool_call>call:{toolName}
content: JSONSchema(original request schema)
end:     <tool_call|>
```

The semantics are:

```text
free model intent
    ↓
<|tool_call> trigger
    ↓
request-visible tool-name enforcement
    ↓
request JSON-Schema enforcement
    ↓
completed native tool tag
    ↓
free generation again
```

Or, more compactly:

> **Before trigger: discretion. After trigger: correctness.**

This preserves the meaning of OpenAI `tool_choice=auto`: a tool call remains optional, but once the model commits to the native tool-call channel, function selection and argument structure become constrained.

No parser code was changed by `80b885`.

---

## 7. Why `TriggeredTags` is native OVMS architecture

The strongest upstream argument is not that llama.cpp implements lazy Gemma4 grammar.

The stronger argument is that **OVMS already has the same architectural pattern**.

At the pinned upstream OVMS source, sibling generation builders already use `StructuredOutputConfig::TriggeredTags` with their own model-specific trigger boundaries:

| Builder family | Model-specific trigger concept |
|---|---|
| Llama3 | JSON/function-name prefix trigger |
| Hermes3 / Qwen3 | `<tool_call>` |
| Phi4 | `functools` |
| Devstral | `[TOOL_CALLS]` |
| proposed Gemma4 mapping | `<|tool_call>` |

Therefore the change is not a new structured-generation subsystem. It applies an existing OVMS/OpenVINO abstraction to a model family that already has an explicit native tool boundary.

The maintainer-facing question becomes:

> **Why should Gemma4 remain the exception that drops structured generation for `auto` when OVMS already has exactly the conditional-tool-region abstraction it needs?**

llama.cpp is useful as independent behavioral evidence. The implementation itself remains native to OVMS/OpenVINO.

---

## 8. Generator evidence matrix

| Requirement | Canonical / API meaning | Independent runtime evidence | OVMS / OpenVINO mechanism | Fork implementation | Contract evidence | Runtime evidence |
|---|---|---|---|---|---|---|
| `auto` remains optional | caller permits either prose or tool use | llama.cpp Gemma4 uses lazy grammar for non-required choice | `TriggeredTags` with `at_least_one=false` | `80b885` | `bc4cd8c...` auto guided-generation contract | pending for exact lazy implementation |
| native trigger activates constraints | Gemma4 call region starts at `<|tool_call>` | llama.cpp uses the same native trigger boundary | `TriggeredTags.triggers` | trigger `<|tool_call>` | exact-trigger assertion | pending |
| only request-visible tools are legal | OpenAI request tool registry is authoritative | peer runtimes restrict available tools | structural `Tag` set generated from request tools | per-request tags | request-tool-only assertions | pending |
| arguments obey exact tool schema | OpenAI tool schema is authoritative | peer runtimes guide/validate tool arguments | `JSONSchema(original request schema)` | schema delegated unchanged | nested/array/enum/nullable preservation tests | pending |
| `required` cannot fall back to prose-only | OpenAI hard-choice contract | peer runtimes force tool path | eager structural tags | hard grammar + fail-closed policy | hard-choice regression tests | covered by accepted predecessor line |
| named choice cannot select another function | named tool is caller-selected | peer runtimes restrict function set | structural tag set narrowed to one tool | named hard grammar | named-choice tests | covered by accepted predecessor line |

---

## 9. Generator TDD evidence

The lazy-auto contract was committed before the implementation:

```text
bc4cd8c08749d861651aca278d50aa8dbb185789
    test(gemma4): specify auto guided-generation contract
```

At that commit the expected `auto` behavior is source-level RED because the predecessor resets structured output for auto.

Implementation follows at:

```text
80b885281443d7b0fd5f3a2f71237a8524d69b04
    fix(gemma4): port lazy-capable auto tool generation
```

The contract covers:

- `auto` produces `TriggeredTags` rather than an absent config;
- trigger is exactly `<|tool_call>`;
- `at_least_one == false`;
- request-visible tool tags only;
- exact request JSON Schema preservation;
- nested objects, arrays, enums and nullable types remain delegated to JSON Schema;
- hard choices remain mandatory;
- optional reasoning remains legal before mandatory hard calls;
- invalid tool choices and schemas fail;
- no empty `ConstString("")` is generated;
- lazy structured output is passed through validation.

The handoff correctly records that no hosted RED run was executed for the test-first commit.

---

# Part II — Parser

## 10. Parser responsibility

The Parser owns interpretation after the model has emitted tokens:

```text
raw Gemma4 assistant output
    ↓
Gemma4ToolParser
    ↓
validated / normalized tool-call object
    ↓
OpenAI-compatible response
```

The Parser can normalize representation. It cannot retroactively change model-generation policy.

For example, it can convert:

```text
<|"|>native string<|"|>
```

into a JSON string, preserve nested arrays and objects, or withhold partial streaming values until their type is stable.

It cannot repair:

```text
tool_choice=required
model emits prose-only EOS
```

because no call exists to parse.

It also cannot safely transform a wrong named function into the requested one or invent schema-valid arguments not emitted by the model.

---

## 11. Existing upstream extension point

OVMS already contains a dedicated `Gemma4ToolParser` selected by the generic output-parser routing.

The fork therefore does not introduce a new parser subsystem. It hardens an existing model-specific extension point.

Historical upstream provenance includes:

```text
0fd950beb3605336fe85a498431bb96c3926472c
    Gemma4 parser / PR #4179

cfe93b394921c7d610266dbfced394db9e078bb7
    incomplete / streaming output recovery / PR #4493

6f5b48ece2078e32268b87402cc206e8b2772da8
    Gemma4 parsing fixes / PR #4508
```

The local hardening continues that same problem line rather than replacing it.

---

## 12. Parser contract-first history

The clearest TDD pair is:

```text
47a3daeb94a2a0444040b292be15c26dcddfc4d2
    test(gemma4): add parser v2 recursive and recovery contracts
        ↓
5e1cda89a48d77a03f859f3932bf55d681ec1306
    feat(gemma4): implement recursive bounded native tool parser
```

The test commit specifies, before implementation:

- recursive arrays of objects;
- scalar type preservation;
- parenthesized arguments only when structurally anchored;
- anchored alternate call-name forms;
- unknown tools must not become executable;
- malformed calls are bounded so a later valid call survives.

The implementation then replaces shallow/string-rewrite behavior with recursive parsing and typed JSON serialization.

That sequence matters upstream because it demonstrates that parser complexity was introduced to satisfy explicit behavioral contracts rather than to accommodate an isolated sample output.

---

## 13. Independent convergence with vLLM

The pinned vLLM Gemma4 parser independently addresses the same classes of problems:

- reasoning plus native tool-call states;
- `<|tool_call>call:func_name{...}<tool_call|>` framing;
- custom Gemma4 string delimiters;
- recursive nested arrays and objects;
- braces inside strings;
- incomplete streaming delimiters;
- partial scalar values whose type is not yet stable.

This is not protocol authority, but it is strong convergence evidence.

Two independent runtimes requiring dedicated recursive Gemma4 parsing is more persuasive than treating the behavior as a fork-specific oddity.

---

## 14. Parser evidence matrix

| Requirement | Canonical / observed protocol | Independent implementation | Existing OVMS abstraction | Fork contract | Fork implementation | Accepted evidence |
|---|---|---|---|---|---|---|
| native call envelope | `<|tool_call>call:name...<tool_call|>` | vLLM dedicated Gemma4 state machine | `Gemma4ToolParser` | anchored call tests | parser v2 | accepted line |
| native strings | Gemma4 custom string delimiters | vLLM custom string parsing | model-specific parser | native-value tests | recursive parser | accepted line |
| nested arrays/objects | recursive tool arguments | vLLM recursive parser | parser extension point | recursive array/object contract | `NativeValueParser` style recursive descent | accepted line |
| scalar typing | bool/null/int/float semantics | vLLM withholds unstable partial values | typed JSON output | scalar-preservation contract | RapidJSON serialization | accepted line |
| malformed-call boundary | native end marker defines recovery boundary | peer state-machine recovery | parser state | later-valid-call-survives test | bounded recovery | accepted line |
| unknown function safety | request registry is authority | peer runtimes use request tools | tool registry passed into parser | unknown-tool rejection test | registry validation | accepted line |
| reasoning to call | Gemma4 may reason before tool region | vLLM explicit state transition | reasoning parser + tool parser | transition contracts | routing fixes | accepted line |

---

## 15. Parser tolerance vs execution safety

Parser tolerance must not become execution tolerance.

The intended rule is:

> **Tolerance is applied to serialization, not to execution authority.**

The parser may tolerate tightly bounded representation variants, such as:

- native string encoding;
- recursive value forms;
- supported parenthesized arguments when anchored by native protocol state;
- incomplete streaming fragments;
- reasoning followed by a call.

Execution promotion remains strict:

- no fuzzy function-name matching;
- no scanning arbitrary prose for executable `call:` substrings;
- function names checked against the request-visible registry;
- malformed calls bounded by protocol state/end markers;
- arguments emitted only after sufficient parse completion.

The contract `DoesNotEmitUnknownToolAsExecutableCall` is especially important: tolerance in syntax must never expand the caller's execution authority.

---

# Part III — Ownership, blast radius and upstream case

## 16. Why Parser-only fixes were insufficient

Parser hardening can repair representation that actually exists.

It cannot repair generation-policy failures such as:

```text
required request
    -> model never enters tool region
```

or:

```text
named tool B
    -> model emits tool A
```

or:

```text
schema enum = ["low", "high"]
    -> model emits "medium"
```

without inventing behavior that was not generated.

The responsibility boundary is therefore:

```text
Generation correctness
    -> Generator / xgrammar

Representation recovery
    -> Parser

Execution authorization
    -> request registry + Parser
```

This is why Generator and Parser hardening are complementary.

---

## 17. Failure taxonomy

A useful debugging taxonomy is:

```text
G = Generator
T = Template
M = raw Model behavior
P = Parser
W = Wiring
V = structured-output validation / xgrammar
```

The rule is:

> Classify the failure at the first boundary where observed state becomes inconsistent with the expected contract.

Examples:

| Symptom | Primary owner |
|---|---|
| `required`, but raw output is prose-only | **G** |
| correct native call loses nested array in OpenAI response | **P** |
| correct builder/parser exist but request registry is not passed to parser | **W** |
| model reasonably answers prose under `auto` | not necessarily a failure |
| stale/incompatible special-token layout causes malformed protocol | **T** |
| xgrammar rejects an empty `ConstString("")` used by a generated grammar | **V/G** |

This avoids fixing downstream symptoms in the wrong subsystem.

---

## 18. Minimality and blast radius

At the `80b885` lazy-auto implementation point, the production change is intentionally narrow:

```text
src/llm/io_processing/generation_config_builder.hpp
src/test/llm/generation_config/gemma4_generation_contract_test.cpp
```

Parser changes at that implementation point:

```text
NONE
```

The change does not:

- replace the generic OpenAI API layer;
- add a new grammar engine;
- copy llama.cpp PEG/sampler/parser code;
- change other model builders;
- bypass OpenVINO GenAI validation.

It uses existing OVMS extension points and existing OpenVINO structured-generation machinery.

The working branch has since advanced beyond `80b885`. Current hardening carries `parallel_tool_calls` through the OpenAI request path and maps it onto structural-tag repetition policy. That later work must be reviewed and accepted on its own exact head; it is not evidence that `80b885` itself had already solved the later API surface.

See [`docs/superpowers/plans/2026-09-07-gemma4-generator-hardening.md`](../superpowers/plans/2026-09-07-gemma4-generator-hardening.md).

---

## 19. Explicit non-claims

This report does **not** claim:

- that the current moving feature-branch HEAD has the same acceptance status as `fea1`;
- that `80b885` has already passed the recorded 100/100 runtime gate;
- that llama.cpp or vLLM define the Gemma4 protocol;
- that the Parser should recover arbitrary malformed assistant text;
- that all serialization variants are executable;
- that other model builders require behavior changes;
- that a new grammar engine is necessary.

These limits are part of the technical case, not weaknesses to hide.

---

## 20. Maintainer objections and answers

### Why not use generic JSON Schema output?

Because a complete Gemma4 assistant turn is not a JSON document. The tool argument region is schema-constrained; reasoning, prose and native call framing are not.

### Why not leave `auto` entirely unconstrained?

Because that preserves optionality but cannot enforce function/schema correctness once the model has already committed to a native tool call.

Lazy triggered generation preserves both:

```text
before trigger: discretion
after trigger: correctness
```

### Why rely on llama.cpp?

We do not rely on it as an API or protocol authority. llama.cpp independently demonstrates the same lazy Gemma4 behavior. The OVMS implementation uses native OpenVINO `TriggeredTags`, already used by upstream sibling builders.

### Why model-specific code?

OVMS already uses model-specific generation builders and already contains `Gemma4ToolParser`. Gemma4 has model-specific reasoning markers, tool markers, strings and call framing, so the existing extension points are the appropriate location.

### Why tolerate non-canonical parser forms?

The Generator remains canonical. The Parser is narrowly tolerant only where output is strongly protocol-anchored or needed for streaming/recovery. Execution authority remains strict.

### Does this affect other models?

The lazy change is Gemma4-specific and consumes a generic primitive without changing sibling builder semantics.

### Has the lazy Generator passed the existing 100/100 acceptance?

No. That evidence belongs to exact accepted SHA `fea1a5f1...`. The lazy implementation point `80b885...` and later branch hardening require their own runtime acceptance.

---

## 21. Proposed upstream review split

The work is easier to review if presented as logically separable units.

### PR A — Gemma4 Parser hardening

Scope:

- recursive native values;
- scalar type preservation;
- native strings;
- bounded malformed-call recovery;
- request tool-registry validation;
- streaming robustness;
- reasoning-to-call transitions.

Representative TDD pair:

```text
47a3daeb...  parser contracts
    ↓
5e1cda89...  recursive bounded parser implementation
```

Review framing:

> hardening of the existing upstream `Gemma4ToolParser`, not a new parser subsystem.

### PR B — hard tool-choice generation contracts

Scope:

- `required`;
- named choice;
- mandatory native tool generation;
- fail-closed structured-output policy;
- optional reasoning before mandatory calls.

Review framing:

> explicit OpenAI hard-choice contracts should not silently degrade into unconstrained generation.

### PR C — lazy `tool_choice=auto`

Scope:

```text
auto
    -> TriggeredTags
trigger
    -> <|tool_call>
at_least_one
    -> false
```

Later hardening should additionally honor `parallel_tool_calls` by mapping the request policy onto `stop_after_first` rather than assuming repeatable calls unconditionally.

Review framing:

> apply the existing OVMS conditional-tool-region primitive to Gemma4's existing native trigger.

---

## 22. Proof obligations for exact runtime acceptance

The next acceptance report should prove architectural properties, not only aggregate HTTP success.

### Parser obligations

```text
P1  nested native values reconstruct correctly
P2  scalar types survive normalization
P3  malformed calls cannot consume later valid calls
P4  unknown functions are not promoted to executable calls
P5  streaming partial values do not create invalid stable deltas
P6  reasoning-to-call phase transitions remain correct
```

### Hard Generator obligations

```text
G1  required cannot terminate as prose-only output
G2  named choice cannot emit another function
G3  hard structured policy cannot silently disappear on validation fallback
G4  optional reasoning can precede the mandatory call
```

### Lazy Generator obligations

```text
L1  auto permits ordinary prose without a tool call
L2  auto can naturally enter <|tool_call>
L3  after trigger, unavailable tool names are impossible
L4  after trigger, JSON-Schema violations are prevented
L5  reasoning can precede prose or a triggered call
L6  call-count policy follows parallel_tool_calls
L7  streaming preserves trigger/parser boundaries
L8  tool-response continuation preserves the same policy
L9  validation did not silently remove the lazy constraint
```

For `parallel_tool_calls=false`, acceptance must verify at most one tool call in the assistant turn. For `parallel_tool_calls=true`, repeatable calls must remain possible where the model/request naturally needs them.

HTTP 200 is insufficient evidence for `L9`: logs or equivalent instrumentation must prove that the structured policy remained active and did not silently fall back to unconstrained generation.

---

## 23. Exact acceptance boundary

The evidence must retain three distinct coordinates:

```text
ACCEPTED PREDECESSOR / RUNTIME EVIDENCE
    fea1a5f1c2640aa60fe6a840d3f62b38fb7b7767

LAZY-AUTO IMPLEMENTATION POINT
    80b885281443d7b0fd5f3a2f71237a8524d69b04

CURRENT WORKING BRANCH
    feature/gemma4-llamacpp-auto-generator-port
    (continued hardening beyond 80b885)
```

The lazy-auto handoff explicitly records as **NOT RUN** at its implementation point:

- focused Bazel compile/test execution;
- Windows OVMS build;
- target OpenVINO GenAI/xgrammar validation on Arc;
- Gemma4 26B-A4B live inference;
- streaming acceptance;
- chained continuation;
- multi-call live acceptance.

That list must not be rewritten into PASS by later narrative.

---

## 24. Consolidated provenance table

| Concern | Protocol / API | Peer-runtime evidence | Native OVMS/OpenVINO mechanism | Fork implementation | Contract | Runtime status |
|---|---|---|---|---|---|---|
| optional `auto` | OpenAI allows prose or tool | llama.cpp lazy Gemma4 grammar | `TriggeredTags` | `80b885` | `bc4cd8c` | exact lazy acceptance pending |
| trigger boundary | Gemma4 `<|tool_call>` | llama.cpp same boundary | trigger list | `80b885` | exact-trigger assertion | pending |
| request-tool restriction | request registry | vLLM/llama tool set | structural tags | `80b885` | request-tool-only tests | pending |
| schema enforcement | per-tool JSON Schema | guided peer runtimes | `JSONSchema` structural content | `80b885` | schema-preservation tests | pending |
| hard required | OpenAI hard contract | peer forced-tool behavior | eager tags | predecessor generation commits | hard-choice contracts | accepted predecessor evidence |
| native strings | Gemma4 serialization | vLLM custom strings | Gemma4 parser | parser v2 | parser contracts | accepted line |
| recursive values | native nested args | vLLM recursive parser | parser extension point | `5e1cda89` | `47a3daeb` | accepted line |
| scalar typing | native scalar semantics | vLLM partial stability | typed JSON output | parser v2 | scalar contract | accepted line |
| malformed boundary | native end marker | peer state recovery | parser state | parser v2 | bounded-recovery contract | accepted line |
| unknown tool | request authority | peer request-tool sets | registry wiring | parser v2 | unknown-tool rejection | accepted line |
| reasoning -> call | Gemma4 channel transition | vLLM state transition | reasoning + tool parsers | transition fixes | transition tests | accepted line |
| parallel call policy | OpenAI `parallel_tool_calls` | standard tool API behavior | `stop_after_first` | post-`80b885` hardening | dedicated OpenAI + Gemma4 contracts | requires exact-head acceptance |

---

## 25. Final maintainer-facing formulation

The proposed work should be reviewed as localized Gemma4 integration hardening, not as a new tool-calling architecture.

The Parser changes strengthen OVMS's existing `Gemma4ToolParser` so that native recursive arguments, scalar types, streaming fragments and bounded recovery are handled without weakening execution authority.

The Generator changes map OpenAI intent onto Gemma4-native generation policy:

```text
none
    -> no tool constraint

auto
    -> free generation until the native tool trigger,
       then constrained tool name and arguments

required
    -> mandatory tool generation

named
    -> mandatory generation of the selected tool only
```

For `auto`, the implementation uses OpenVINO GenAI `TriggeredTags`, the same architectural primitive already used by several upstream model-specific builders. The Gemma4-specific contribution is therefore limited to its native trigger and structural tag composition.

The design was informed by independent Gemma4 behavior in llama.cpp and vLLM, but those projects remain compatibility evidence rather than protocol authority.

The resulting rules are deliberately asymmetric:

> **Canonical Generator. Tolerant but execution-strict Parser.**

and deliberately evidence-bound:

> **Accepted predecessor evidence and later lazy-generator evidence remain separate until the later exact head is rebuilt and exercised on the target runtime.**
