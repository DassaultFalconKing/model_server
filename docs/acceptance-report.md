# Acceptance report — GEMMAMONSTER Frankenstein experimental probe

## Verdict

`FRANKENSTEIN_TAB_LOOP_NOT_FIXED`

Candidate `c5115ba494729f5af40d3ab733c8e49c339932b0`, tree `b88f6b22b7b63d9cabb9ab7c383f879d5696b3c8`, was run on OVMS `2026.5.0-23005-9b1d5c9494e` with OpenVINO GenAI `2026.5.0.0-1-2e3b291a30e` and tokenizers `2026.5.0.0-740-4813f2b8dac`.

## Findings

- Startup reached AVAILABLE in 30.748 seconds; `/v3/models` returned HTTP 200.
- Basic chat, one tool call, two parallel calls, nested JSON, and real `{}` passed before the fault.
- Strict eight-call payload passed at temperatures 0.0, 0.3, 0.7 and 1.0.
- The deterministic parallel-2/3/4 and repeated-tool surface cases ended by length with zero calls.
- TRACE for `prompt-strict-temp0` recorded 172 consecutive `[255970,107]` tab/newline pairs: 344 decoded whitespace characters. The request reached 256 generated tokens and ended `finish_reason=length` without a completed call.
- A subsequent GPU `CL_OUT_OF_RESOURCES` / `could not execute a primitive` fault was classified as `GPU_EXECUTION_FAILURE`; the executor was quarantined. PID 33812 and `/v3/models` survived; post-fault chat and tool requests correctly failed with HTTP 400 requiring reload/recreation.
- Source contains the containment implementation, but its available test binary exited `-1073741515` before gtest inventory.

See raw request/response objects, summaries, full server logs, and the bounded trace excerpt in this archive.