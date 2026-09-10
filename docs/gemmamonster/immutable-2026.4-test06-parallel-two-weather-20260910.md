Immutable 2026.4 Test06 Parallel Weather
========================================

Status: FAIL_NO_TOOL_CALL

Date: 2026-09-10

Runtime under test:

- Package: `C:\git\artifacts\ovms-gemma4-2026.4.0.a08b30bdb-E-MINJA`
- Binary: `ovms\ovms.exe`
- SHA256: `8DE88D505A619EB7134DEB3FB86BFD415A6FC3715BE2E7ACDF81EA239A88F632`
- OVMS version: `2026.4.0.a08b30bdb`
- OpenVINO GenAI backend: `2026.4.0.0-3401-5f7f1278107`
- Active process: PID `33656`
- Active API model: `gemma4-26-heretic`
- Ports: REST `8888`, gRPC `9000`

Generated graph facts:

- `device: "GPU"`
- `pipeline_type: VLM_CB`
- `chat_template_mode: MINJA`
- `max_num_seqs: 1`
- `enable_prefix_caching: true`
- `max_tokens_limit: 65536`
- `plugin_config: {"DYNAMIC_QUANTIZATION_GROUP_SIZE":"0","PERFORMANCE_HINT":"LATENCY","KV_CACHE_PRECISION":"u8"}`

Test request:

- Case: `06_parallel_two_weather`
- Shape: one logical `weather({city})` tool, prompt asks for Paris and Berlin
- `tool_choice: auto`
- `parallel_tool_calls: true`
- `max_tokens: 96`
- `temperature: 0`
- `seed: 206`

Observed response:

- HTTP status: `200`
- Elapsed: `4.739s`
- `finish_reason: "length"`
- `message.content: ""`
- `message.tool_calls: []`
- Usage: `prompt_tokens=145`, `completion_tokens=96`, `total_tokens=241`

Interpretation:

The immutable 2026.4 runtime did not reproduce the Gate12 frozen `.5` GPU OOM
failure on this exact case. It also did not pass semantic tool-calling
acceptance: the server returned HTTP 200 but emitted no tool calls and stopped
only because `max_tokens` was exhausted.

Raw evidence:

- `docs/gemmamonster/evidence/immutable-2026.4-test06-20260910T0531Z/06_parallel_two_weather.request.json`
- `docs/gemmamonster/evidence/immutable-2026.4-test06-20260910T0531Z/06_parallel_two_weather.response.json`
- `docs/gemmamonster/evidence/immutable-2026.4-test06-20260910T0531Z/ovms-process-after.json`
- `docs/gemmamonster/evidence/immutable-2026.4-test06-20260910T0531Z/ovms-log-tail-after-test06.txt`
