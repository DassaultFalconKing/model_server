# GEMMAMONSTER stable 2026.4 RC2 refit handoff

## Current source line

- Branch: `integration/gemmamonster-2026.4-latest-refit`
- Base: `9eb93f15fecb848d399f17c7a6a6626e5a1498d7`, the latest maintainer 2026.4 source state before upstream moved packaging to 2026.5.
- Runtime line: maintainer 2026.4 RC2 from `versions.mk`, not known-good RC1 and not 2026.5.

## What has been refitted

The branch carries the advanced Gemma4 protocol stack from the accepted 2026.5 line and the later accepted `fde0762` delta, while preserving the 2026.4 RC2 runtime pins:

- Gemma4 native tool parser.
- Gemma4 native reasoning parser.
- OutputParser routing and parser-owned tool-call boundaries.
- Post-render Gemma4 prompt-state grammar adaptation.
- Special-token streamer handoff across reasoning to tool-call phase.
- Gemma4 guided generation builder with `TriggeredTags`, hard/named grammar, optional thought-before-tool branch, fail-closed hard choices, and `parallel_tool_calls` propagation.
- Single-tool repeated-call grammar workaround from `fde0762`: when `parallel_tool_calls=true` and only one tool schema is present, the tag list is duplicated so xgrammar can re-enter the same tool.
- Parser, recovery, streamer, generation, prompt-state, overlay, and OpenAI parallel-tool-call contracts are present in-tree.
- Persistent session continuity has also been restored on this branch as a separate later refit slice. Treat it as acceptance-critical rather than silently assuming it is safe because the code compiled somewhere in the multiverse.

## Runtime rule

Do not run or accept a bare `bazel-bin/src/ovms.exe` as a runtime candidate.

A candidate is acceptable only as a package root containing:

```text
candidate-root/
├── ovms/
│   ├── ovms.exe
│   ├── openvino.dll
│   ├── openvino_genai.dll
│   ├── openvino_tokenizers.dll
│   └── ...
├── manifest.json
├── SHA256SUMS.txt
├── logs/
├── provenance/
├── acceptance/
└── dumps/
```

The package `ovms/` directory is the runtime unit. Loaded `openvino*`, `genai`, `tokenizers`, and `tbb` DLLs must come from that directory during acceptance.

## Build command

```powershell
cd C:\git\model_server-gemma4-fast
git fetch origin
git switch integration/gemmamonster-2026.4-latest-refit
git reset --hard origin/integration/gemmamonster-2026.4-latest-refit

.\scripts\gemmamonster\build-stable-candidate.ps1 `
  -ShortRoot g54 `
  -Label gemma4-stable-2026.4-rc2 `
  -ExpungeDependencies `
  -WithoutTests
```

Remove `-WithoutTests` once the local Windows test environment has the required test tokenizers and Bazel test prerequisites.

## Launch command

```powershell
.\scripts\gemmamonster\launch-stable-candidate.ps1 `
  -CandidateRoot C:\gemmamonster-artifacts\candidates\2026.4-rc2\<candidate> `
  -ModelPath "C:\llm\models\OpenVINO\Wondernutts\gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov" `
  -ModelName gemma4-26-heretic `
  -RestPort 8000
```

If the simple `--task text_generation` launch is not sufficient for the local VLM_CB model graph, pass the exact OVMS args through `-OvmsArgs`. The launcher still verifies the candidate manifest, hashes, and loaded runtime modules.

## Required acceptance before known-good

1. Build/package provenance is clean: `manifest.json`, `SHA256SUMS.txt`, `ovms --version`, no 2026.5 runtime component.
2. Bazel contract tests pass for:
   - `//src/test/llm/gemma4_fast:gemma4_parser_contract_test`
   - `//src/test/llm/generation_config:gemma4_generation_contract_test`
   - `//src/test/llm/generation_config:gemma4_prompt_state_generation_contract_test`
   - `//src/test/llm/generation_config:openai_parallel_tool_calls_contract_test`
   - `//src/test/llm/gemma4_overlay:gemma4_chat_template_overlay_contract_test`
3. REST protocol acceptance passes for:
   - single tool call;
   - distinct parallel tool calls;
   - repeated same-tool calls, non-streaming;
   - repeated same-tool calls, streaming;
   - tool-result continuation;
   - multi-turn session continuity with tool results.
4. Real OpenCode workload on Arc 140V does not hang the machine.

## Guardrails

- Do not downgrade this branch to the known-good RC1 runtime unless doing an explicit A/B branch.
- Do not import 2026.5 OpenVINO/GenAI pins into this branch.
- Do not declare the branch known-good on source diff alone. The whole point is to stop worshipping binaries of unknown parentage like tiny cursed idols.
