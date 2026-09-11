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
