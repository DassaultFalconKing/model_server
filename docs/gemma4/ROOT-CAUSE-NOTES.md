# Gemma4 chained tool calling: root-cause investigation notes

Status: investigation in progress. These are hypotheses/evidence, not accepted fixes.

## Code-level observations

1. `Gemma4GenerationConfigBuilder` treats `auto` differently from `required`/named:
   - `required`/named build structural tool tags and set `at_least_one=true`.
   - `auto` explicitly resets `structured_output_config` and returns.
   - Therefore `auto` tool invocation is a model action-selection decision with no generation-time tool-call enforcement.

2. Sampling can vary requests when callers omit generation controls:
   - Base generation config is inherited from model configuration.
   - request temperature only overrides it when explicitly supplied.
   - `do_sample` is enabled when effective temperature > 0 and beams == 1.
   - when sampling and request seed is omitted, OVMS deliberately chooses a fresh random seed.
   - This can produce apparent "every other time" behavior in unconstrained `auto` calls even with identical semantic inputs.

3. Parser recognition is downstream and has a deliberate boundary:
   - canonical `<|tool_call>` is searched in content;
   - bare `call:` is accepted only exactly at the parser phase entry position;
   - a model that emits prose and later emits bare `call:` may have attempted a tool action that is intentionally not promoted to an executable call.
   - Raw-token/verbose evidence is required before attributing failures to the parser.

4. Exact structured tool results improve grounding:
   - JSON-object tool result content is converted to a mapping for compatible Gemma4 templates.
   - The Gemma4 template renders mapping leaves as native fields rather than one escaped JSON string.
   - The accepted live chain propagated the exact 40-character commit SHA while surrounding generated evidence fields still contained hallucinations.

## Template / protocol observation

The current Wondernutts Gemma4 template supports both native Gemma `tool_responses` and OpenAI Chat Completions `role:tool` messages. It resolves `tool_call_id`, renders a structured mapping as `response:<tool>{key:value,...}`, and keeps the tool response in the model-turn protocol. This is consistent with Google's Gemma4 function-calling guidance, which recommends structured `tool_responses` so the template can emit native response tokens.

## Research alignment

- BFCL V3/V4 separates single-turn function syntax from multi-turn/agentic behavior and evaluates state/trajectory outcomes, supporting our separation of parser correctness from action-selection correctness.
- tau-bench reports high run-to-run inconsistency and proposes pass^k, supporting repeated-trial reliability measurement rather than one-shot PASS.
- ToolSandbox identifies state dependency and canonicalization as distinct hard problems in multi-turn tool use, matching our exact-value/provenance direction.
- SWE-agent shows that agent-computer interface design materially changes agent performance; structured exact facts are an observation-interface design choice, not merely prompt engineering.
- ToolACE uses rule/model verification layers around function-calling data, supporting server-side verification of exact grounded fields rather than trusting free generation.
- Recent work on joint structured-output/tool constraints reports possible tool suppression under grammar token masks. This is relevant as a warning for any future attempt to constrain `auto`; simply applying a JSON grammar to the whole turn may make action tokens unreachable. Any `auto` enforcement experiment must test this explicitly.

## Immediate falsifiable hypotheses

- H1: With `temperature=0`, `auto` reliability rises materially relative to inherited/positive-temperature sampling.
- H2: Conditional on the model entering canonical `<|tool_call>`, parser recognition is near-deterministic and substantially more reliable than action selection.
- H3: Grounded exact-value fidelity conditional on the intended parsed call is substantially higher than full semantic payload correctness.
- H4: Expanding structured tool-result mappings to IDs, paths, counts, enums, timestamps and nested scalar leaves preserves exact values better than free-text reconstruction.

See `docs/gemma4/local-agent-grounded-facts-test-handoff.md` for the required test campaign.
