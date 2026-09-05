# Gemma4 RC1 reviewed contracts status

Date: 2026-09-05
Branch: `fix/gemma4-rc1-reviewed-contracts`
Status snapshot parent: `eb458a18f1f9b35aaab9d5f83fb5e41d7d96e780`
Runtime-proven predecessor: `0a537f08987a3df4c0254c1614162c06ac20b968`
OVMS 2026.4 RC1 base: `530dc63f816507d18bc14629e8cffeb55e3985e6`

## Completed review work

- P1-A guided-JSON boundary scanning is implemented in the Gemma4 tool parser. Guided JSON uses an incremental container/string/escape-aware scanner instead of the native Gemma delimiter scanner. Native Gemma fallback remains separate.
- P1-B reasoning-to-tool routing is implemented as an explicit parser capability. The default is disabled; Gemma4 opts in, so a parser-owned complete tool-start marker can terminate an open reasoning phase without changing other reasoning/tool parser combinations.
- `Gemma4GenerationConfigBuilder` has been relocated from the common builder header into Gemma4-specific source/header files with production BUILD wiring.
- Gemma4 builder contracts have been hardened: named choices validate/select the requested schema; required/named choices require an enforceable schema; guided schemas must be JSON objects; active tool grammar is not silently combined with `response_format` grammar.
- Parser regression tests are in the canonical output-parser test lane.
- Gemma4 generation-builder contract tests are now exposed as the dedicated Bazel target `//src/test/llm/generation_config:gemma4_generation_contract_test`.

## Commit checkpoints reviewed

- `62a3d71de4ac7d20074c8ee5830b764e3d6afdce` - reviewed regression contracts and implementation plan.
- `a051dbf9182d2f2ca61fa44a66b1de06ef67f118` - P1-A guided JSON boundary scanner.
- `7b5b73be59a0ab764df5468e75c09069768efd2c` - P1-B capability routing, builder relocation, BUILD wiring, builder contracts.
- `8f1abcd7dcfc86abb9844e9fa0a8c2683d051406` - explicit Gemma4 generation-builder validation contracts.
- `eb458a18f1f9b35aaab9d5f83fb5e41d7d96e780` - current pre-fix review head, including dedicated Bazel builder-test wiring.

## Remaining blocking contract issue

The request-to-generation boundary still permits a hard tool-choice constraint to degrade silently. After the builder creates structured output, `extractInputRequest` validates the structured-output configuration and the existing fallback path can unset invalid structured output and continue generation. For `tool_choice=required` or a named tool choice this re-opens unconstrained prose generation and violates the hard-choice contract.

Required repair:

- builder/request validation errors must become a normal API invalid-request result rather than escaping or silently weakening the request;
- `required` and named tool choices must fail closed when structured-output validation fails;
- `auto` may retain the existing fail-open structured-output fallback because tool invocation is optional;
- `none` remains unaffected;
- add request-level regression coverage proving the distinction.

## Acceptance boundary

This snapshot is an engineering review checkpoint, not a new accepted runtime head. No claim is made here that a fresh Windows build, Intel GPU runtime, Heretic tool-choice matrix, or NovaClaw streaming acceptance has passed at this head. Those tests are intentionally left to the local host acceptance lane after the remaining request-boundary fix is committed.

The 4.6 KB / Intel GPU failure remains a separate runtime-recovery track and is not part of this contract-repair change set.
