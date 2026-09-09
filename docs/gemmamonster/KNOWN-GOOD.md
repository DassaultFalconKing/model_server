# Gemmamonster Known-Good Registry

This registry records what can honestly be called known-good. It is intentionally stingy. If that feels rude, blame entropy.

## Status vocabulary

| Status | Allowed claim |
| --- | --- |
| `source_only` | source ref exists; no build/test/runtime claim |
| `built_not_accepted` | binary hash exists; protocol/live behavior not accepted |
| `protocol_pass` | required protocol tests passed for exact candidate evidence |
| `live_pass` | live REST/model loop passed for exact candidate evidence |
| `known_good` | bundle, logs, source SHA, binary hash, model/runtime details recorded |
| `rejected` | failed, superseded, or unverifiable |

## Current entries

### 2026-09-09 source candidate after Gate 1/2 source port

```text
Source SHA:
e398363c2fe6f572a0fdc3ed9fd37c551fd73c76

Branch:
integration/gemma4-parser-generator-refit-next

Status:
source_only

What is present:
- Google Jinja semantic contract is wired into the protocol runner.
- Content-owned boundary routing and dofix semantics are ported at source level.
- Port contract documents the source branch `671f84c25...` evidence separately from target evidence.

Allowed claims:
- source branch contains the semantic port;
- target test branch exists for Gate 1/2 verification;
- machine verification is pending.

Forbidden claims:
- build PASS;
- `//src:llm_output_parser_tests` PASS;
- protocol runner PASS;
- live OVMS REST PASS;
- CodeSleuth/NovaClaw dogfood PASS;
- known-good runtime.

Artifacts:
none yet.
```

### Historical external/source evidence, not target acceptance

```text
Source branch:
fix/gemma4-content-owns-boundaries-routing

Source dofix tip:
671f84c255ea41fd3431a02237cb0e3a0da52700

Reported source verification:
61/61 Gemma4 parser tests and 14/14 generation contracts green.

Scope:
This certifies the source branch report only. It does not certify `integration/gemma4-parser-generator-refit-next` or any binary built from it.
```

## Entry requirements for `known_good`

A future known-good entry must include:

```text
source_sha
branch
binary_sha256
candidate_manifest_path
evidence_bundle_sha256
build command and exit code
protocol summary and exit code
runtime launch command
model path or model revision
REST smoke results
known unrelated failures
promotion decision
```

Missing one of those fields means the entry is not known-good. It may be promising, haunted, or emotionally supportive, but not known-good.
