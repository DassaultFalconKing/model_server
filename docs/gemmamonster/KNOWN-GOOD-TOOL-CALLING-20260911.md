# KNOWN GOOD: Gemma4 26B tool calling

Scope: tool-call selection, parsing, and one complete tool-result continuation loop. This is not a general model-quality or external-tool acceptance claim.

## Frozen combination

- Source SHA: `9a1626260614f68a6282b6799842d5152f0dcdff`
- OVMS version stamp: `2026.4.0.9a1626260`
- Candidate: `9a162626-maintainer-rc2-gemma4-stable-rc2-lean-20260910T235114Z`
- Binary SHA-256: `E7D8024F4F385B8DA5051C343DA3ACE0FBEF65813767EFB74C7FCCFFEE80CB0A`
- Model: `gemma4-26-heretic`
- Model path: `C:\llm\models\OpenVINO\Wondernutts\gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov`
- Pipeline: `VLM_CB`
- Parser flags: `--tool_parser gemma4 --reasoning_parser gemma4`
- Endpoint: `http://127.0.0.1:8006/v3/chat/completions`
- Sampling: `temperature=1.0`, `top_p=0.95`, `top_k=64`, `max_tokens=256`
- Multiplicity: `parallel_tool_calls=false`

Launch command is frozen in candidate acceptance evidence:
`C:\gemmamonster-artifacts\candidates\2026.4\9a162626-maintainer-rc2-gemma4-stable-rc2-lean-20260910T235114Z\acceptance\20260911T012105Z\launch.json`.

## Behavioral evidence

- Forced uncached tool call: HTTP 200, `finish_reason=tool_calls`, `get_weather({"location":"Berlin"})`.
  Evidence: `C:\git\gemmamonster-2026.4-session-evidence\toolcall-probes\20260911T013711Z-gemma4-26-heretic`.
- Two-step agent loop: first response selected `get_weather`; second response consumed the unique synthetic tool result, returned `finish_reason=stop`, made no extra call, and reproduced all grounded values (`17 C`, heavy rain, `31 km/h`).
  Evidence: `C:\git\gemmamonster-2026.4-session-evidence\agentic-loops\20260911T013833Z-gemma4-26-heretic`.

Status: `KNOWN_GOOD_TOOL_CALLING`. Preserve all fields above when using this combination as the comparison baseline.

## Source and reproducible build record

- Repository: `https://github.com/DassaultFalconKing/model_server.git`
- Build source commit: `9a1626260614f68a6282b6799842d5152f0dcdff`
- Source tree: `7237a08cd8fc4bbee3dec4649ca1f01a89be2e6a`
- Source state at build: clean (`repo_dirty=false`)
- Runtime profile: `maintainer-rc2`
- OpenVINO source: `227c33757d1ef95d4da506d00686f923fdd2a535`
- OpenVINO Tokenizers: `a04accf6282d9b304214b492694b18c3979f667a`
- OpenVINO GenAI: `7ea2546852a382cd16bd22dea0cfad2db70ed744`
- Windows GenAI package: `openvino_genai_windows_2026.4.0.0rc2_x86_64.zip`
- Build root: `C:\g54r2`; Python `3.12.10`; Bazel config `win_mp_on_py_on`.

Exact repository entry point:

```powershell
.\scripts\gemmamonster\build-stable-candidate.ps1 `
  -RuntimeProfile maintainer-rc2 `
  -Label gemma4-stable-rc2 `
  -WithoutTests
```

The recorded build ran from `2026-09-10T23:51:18Z` to `23:59:58Z`: Bazel elapsed `519.912s`, critical path `101.07s`, `936` processes, `8,313` actions, and completed successfully. Packaging then ran through `2026-09-11T00:00:41Z`. Do not replace this build record with a warm incremental timing.

Reproduction output must remain `BUILT_PROVENANCE_VERIFIED_NOT_ACCEPTED`; tool-calling acceptance is established separately by the behavioral evidence above.

## Build and package evidence

- Candidate manifest: `C:\gemmamonster-artifacts\candidates\2026.4\9a162626-maintainer-rc2-gemma4-stable-rc2-lean-20260910T235114Z\manifest.json`
- Dependency/build/package logs: sibling `logs\dependencies.log`, `logs\build.log`, and `logs\package.log`.
- Full package hashes: sibling `SHA256SUMS.txt`.
- `ovms.exe`: `e7d8024f4f385b8da5051c343da3ace0fbef65813767efb74c7fccffee80cb0a`
- `openvino.dll`: `def53dd31213fbb75a3d054ed5a244b3e7a984be30183a740787801a97c3ad2a`
- `openvino_genai.dll`: `9d1639af0dc911b25c34f409c0712cd8a0b88362fb8d7d3c09c1033df2e0b60a`
- `openvino_tokenizers.dll`: `ef29a1d5b477819be3e5ab88a13e9ff7b250639a430f186d4b7c3532d9a49807`
- `ovms.zip`: `18ca4d936dd13c34326e54d06f63ee5d1642a7d113852b66cc89719477ceff40`
