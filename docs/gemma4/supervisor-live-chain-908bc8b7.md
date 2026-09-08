# Gemma4 exact-head live chained-tool acceptance

## Scope

Acceptance was executed against exact review SHA
`908bc8b7e3bdd24ddd5eb9b27bbe15bcffb00703` using the freshly built
`bazel-bin/src/ovms.exe` and model `gemma4-26-heretic`.

The tested production path was:

```text
model turn 1 -> inspect_repository_state -> tool result -> model turn 2
-> publish_review_evidence
```

No Gemma4GenerationConfigBuilder or Gemma4ToolParser changes were introduced
in this acceptance iteration.

## Gates

| Gate | Result | Evidence |
|---|---|---|
| Exact checkout/reset | PASS | HEAD `908bc8b7e3bdd24ddd5eb9b27bbe15bcffb00703` |
| Verify build with Python fixture | PASS | `windows_build_fast.ps1 -Mode Verify -WithPython $true`, exit 0 |
| Generation config contract test | PASS | `gemma4_generation_contract_test` |
| Parser contract test | PASS with `GEMMA4_TOKENIZER_PATH` fixture | 16 tests executed successfully in fixture-aware rerun |
| Harness syntax | PASS | `python -m py_compile ab-evidence/live_chain_harness.py` |
| Fresh binary provenance | PASS | runtime build stamp `2026.4.0.908bc8b7` |

The first literal Verify invocation without `GEMMA4_TOKENIZER_PATH` produced
16 tokenizer-initialization failures because the test could not load
`openvino_tokenizer.xml`. This was an environment fixture failure, not a
parser assertion failure. The acceptance rerun supplied the model tokenizer
path and completed successfully.

## Chain results

| Mode | Harness verdict | Request 1 | Executor SHA | Request 2 | Exact SHA |
|---|---:|---|---|---|---:|
| named | PASS | `inspect_repository_state` | exact | `publish_review_evidence` | PASS |
| required | PASS | `inspect_repository_state` | exact | `publish_review_evidence` | PASS |
| auto | PASS | `inspect_repository_state` | exact | `publish_review_evidence` | PASS |

Each request returned HTTP 200. The executor used read-only local inspection
with `allow_network=false` and resolved the requested SHA exactly.

Evidence directories:

- `ab-evidence/live-chain-named/`
- `ab-evidence/live-chain-required/`
- `ab-evidence/live-chain-auto/`

Each contains request inputs, raw responses, tool result, and `summary.json`.

## Supervisor interpretation

The harness-level conclusions are:

- `named PASS`: transport/template/parser chain and exact SHA propagation work.
- `required PASS`: the model selected the correct second tool under mandatory
  tool choice.
- `auto PASS`: the model produced a chained second tool call without a forced
  second tool name.

There is one semantic limitation. The current harness validates the second
tool name and propagated SHA, but does not fully validate every artifact path
and gate inside the generated `publish_review_evidence` arguments. The raw
required/auto responses contain some model-generated paths and dirty-state
claims that are not independently authoritative.

Therefore the recommended supervisor verdict is:

```text
CHAIN TRANSPORT: ACCEPTED
EXACT SHA PROPAGATION: ACCEPTED
AUTONOMOUS SECOND-TOOL SELECTION: ACCEPTED
SEMANTIC EVIDENCE PAYLOAD: FOLLOW-UP HARNESS REQUIRED
FULL AGENT LOOP: DO NOT PROMOTE YET
```

The default harness port `8000` also failed to start on this host; the same
fresh exact-head binary was run on working port `18000` with an explicit base
URL. This port difference is an environment/invocation issue and is recorded
separately from model-chain results.
