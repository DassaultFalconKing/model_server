# Gate12 Frozen Live Acceptance - 2026-09-10

## Verdict

`PARTIAL_PASS_WITH_GPU_OOM_RISK`

Frozen Gate12 passed the live plain-answer, named-tool, auto-single-tool, tool-result-continuation, and reasoning-extraction checks. The final parallel tool-call stress case failed with a transport close and the OVMS log recorded Intel GPU `CL_OUT_OF_RESOURCES`.

This is not a full acceptance pass for parallel tool calling.

## Candidate Identity

- Candidate: `C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z`
- Branch: `test/gemmamonster-gate12-20260909-e398363c`
- Source SHA: `01ea946a5dc8a179a91e8c42e77f0f7a443bc343`
- Binary: `C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\ovms.exe`
- Binary SHA256: `b26120393ceeba469858fb0380409cd715c04dcee58a186420448750cc7164d8`
- Version: `OpenVINO Model Server 2026.5.0.ca84db6b`
- OpenVINO backend: `2026.5.0-23005-9b1d5c9494e`
- OpenVINO GenAI backend: `2026.5.0.0-3421-2e3b291a30e`

## Runtime

- Launch record: `C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\runtime\20260910T031458Z\launch.json`
- Runtime graph: `C:\git\model_server-gemma4-fast\tmp\gemmamonster-ovms\gate12-opencode-fast\graph.pbtxt`
- REST: `http://127.0.0.1:8888`
- gRPC: `9000`
- Device: `GPU`
- Pipeline: `VLM_CB`
- Profile: `E + PERFORMANCE_HINT=THROUGHPUT`
- `OVMS_GRAPH_QUEUE_MAX_SIZE=0`
- `chat_template_mode: JINJA`

The server was started as the only live OVMS process. Older OVMS processes were stopped before launch because the target machine does not have enough resources for two 26B VLM servers.

## Parser Evidence

The live server log contains:

- `Auto-detected tool_parser: gemma4`
- `Auto-detected reasoning_parser: gemma4`
- `Mediapipe: gemma4-26-heretic state changed to: AVAILABLE`

## Live Cases

Evidence directory:

`C:\git\model_server-gemma4-fast\docs\gemmamonster\evidence\gate12-frozen-live-20260910T0320Z`

| Case | Status | Evidence |
| --- | --- | --- |
| Plain semantic answer, `19 + 23` | `PASS` | response content `42`, finish `stop` |
| Named calculator tool, `17 + 25` | `PASS` | one `calculator` tool call, args `{"b":25,"a":17,"op":"add"}` |
| Auto single weather tool, Paris | `PASS` | one `weather` tool call, args `{"city":"Paris"}` |
| Tool-result continuation | `PASS` | answer `Lisbon` from supplied tool result |
| Reasoning extraction, `8 * 9` | `PASS` | final content `72`, non-empty `reasoning_content` |
| Parallel weather tool calls, Paris and Berlin | `FAIL` | client saw connection forcibly closed; OVMS log recorded `CL_OUT_OF_RESOURCES` |

## Failure Evidence

The failing request was:

`C:\git\model_server-gemma4-fast\docs\gemmamonster\evidence\gate12-frozen-live-20260910T0320Z\06_parallel_two_weather.request.json`

The captured client error was:

`C:\git\model_server-gemma4-fast\docs\gemmamonster\evidence\gate12-frozen-live-20260910T0320Z\06_parallel_two_weather.response.json`

The OVMS stdout log recorded:

`onednn_verbose,v1,primitive,error,ocl,errcode -5,CL_OUT_OF_RESOURCES`

followed by:

`Error occurred in LLM executor: ... could not execute a primitive`

## Context Window

The model metadata reports:

- `text_config.max_position_embeddings: 262144`
- `sliding_window: 1024`
- tokenizer `model_max_length` is a sentinel value, not a usable runtime cap

The active Gate12 fast graph explicitly sets:

- `max_tokens_limit: 65536`
- `max_num_seqs: 1`
- `enable_prefix_caching: true`
- `KV_CACHE_PRECISION: u8`

For this launched server, the conservative effective context/output request cap to advertise is therefore `65536` tokens, because the runtime graph limit is lower than the model's theoretical `262144` text position limit.

## Follow-Up

Do not promote this run as full parallel-tool acceptance. The next investigation should treat `parallel_tool_calls=true` on the 26B VLM GPU profile as a resource-risk or scheduler/guided-generation-risk case, separate from the parser correctness that passed in the single-tool and reasoning paths.
