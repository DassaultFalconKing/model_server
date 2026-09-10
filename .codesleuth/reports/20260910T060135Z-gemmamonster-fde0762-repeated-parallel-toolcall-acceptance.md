---
reportType: documentation
targetSha: fde0762ba314dc5f6448726dfce7c533bad9a8a6
provenance: anon
reviewId: none
---

# GEMMAMONSTER fde0762 repeated same-tool parallel-call acceptance

- date: 2026-09-10T06:01:35Z
- target: fde0762ba314dc5f6448726dfce7c533bad9a8a6 (`fix(gemma4): allow repeated same-tool calls with parallel_tool_calls=true`)
- dirty: yes (M *.sh при `git status --ignore-submodules=all`; полный статус без флага невозможен — stale worktree-submodule, см. Limitations)
- scope: runtime acceptance уже собранного `bazel-bin/src/ovms.exe`; cases A/B/C/D + stream + repeatability x5 + memory
- agent: opencode build (Muse Spark)
- provenance: anon (durable review недоступен в этом worktree, личность не выдумывается)
- reviewId: none
- ehaCampaignId: none

## Executive Verdict

**ACCEPTED.** Candidate binary на source `fde0762` проходит все protocol cases: single call, multi-tools/one call, parallel distinct и критический repeated same-tool (`get_weather` Berlin+Munich, `parallel_tool_calls=true`) — в non-stream (5/5 runs) и stream режимах. IDs уникальны, arguments валидны и различны, streaming-индексы независимы, OOM нет. Causal оговорка: в этой сессии сравнения со старым бинарём не было (old binary content перезаписан rebuild'ом, backup нет), поэтому сила causal claim ограничена — см. Final Verdict.

## Source Provenance

- `git rev-parse HEAD` → `fde0762ba314dc5f6448726dfce7c533bad9a8a6` — совпадает с ожидаемым. **Не** `WRONG SOURCE PROVENANCE`.
- Commit: `fix(gemma4): allow repeated same-tool calls with parallel_tool_calls=true`.
- Гипотеза: GEMMAMONSTER раньше некорректно обрабатывал 2+ вызова одного tool в одном assistant turn при `parallel_tool_calls=true`; `fde0762` должен это разрешить без регрессий.

## Binary Provenance

- `C:\git\model_server-gemma4-fast\bazel-bin\src\ovms.exe`, Length `22671872`, LastWriteTime `09/10/2026 7:30:30`.
- `Get-FileHash SHA256` → `9926F8B520704CCF429DEB67F4DFF7A76466A749A1AD1700750BEC0DED968EEA` (повторно сошёлся с ранее зафиксированным).
- `--version` bare (без рантайма в PATH): пустой stdout/stderr, exit `-1073741515` (`0xC0000135 STATUS_DLL_NOT_FOUND`) — зафиксировано как evidence, не как failure бинаря.
- `--version` с PATH `C:\opt\openvino\runtime\bin\intel64\Release` + `3rdparty\tbb\bin` + opencv bin, exit `0`:
  - `OpenVINO Model Server 2026.5.0.ca84db6b`
  - `OpenVINO backend 2026.4.0-22930-61afcb26271-releases/2026/4`
  - `OpenVINO GenAI backend 2026.4.0.0-3401-5f7f1278107`
  - `Bazel build flags: --config=win_mp_on_py_on`

## Build Evidence

`win_incremental_build.log` (135260 bytes, `09/10/2026 7:30:31` — сразу за exe):

- `SOURCE_SHA: fde0762ba314dc5f6448726dfce7c533bad9a8a6`
- `BINARY_SHA256: 9926F8B5...68EEA` (полный выше)
- `BINARY_SIZE: 22671872`
- `BINARY_TIMESTAMP: 09/10/2026 7:30:30`
- `BAZEL_TARGET: //src:ovms` (реальный build: `Analyzing target //src:ovms`, `338 packages, 30073 targets`)
- `BUILD_RESULT: Build completed successfully, 4040 total actions` (`4040 processes: 5 internal, 4035 local`, elapsed 1619.479s, финальный `[8,268/8,269] Linking src/ovms.exe`). `FAILED/ERROR` — совпадений нет.

## Runtime Provenance

Известный deployment из `runtime/gemmamonster-ovms/ovms.command.json` (единственный launcher с command.json; придуманных runtime нет):

- `CURRENT_OVMS_EXE: C:\git\model_server-gemma4-fast\bazel-bin\src\ovms.exe` — **тот же файл, что candidate**.
- args: `--rest_port 8888 --port 9000 --config_path C:\git\model_server-gemma4-fast\runtime\gemmamonster-ovms\config.json`, cwd `C:\git\model_server-gemma4-fast`.
- config: mediapipe `gemma4` → `runtime/gemmamonster-ovms/graph.pbtxt`.
- Запущенных `ovms.exe` до сессии не было (`Win32_Process` пуст) — останавливать было нечего.
- Substitution: копирование не требовалось (deployed path == candidate path). `OLD_BINARY_SHA256: N/A` (отдельного runtime-бинаря нет; контент по этому пути до rebuild'а не бэкапился). `CANDIDATE_SHA256: 9926F8B5...68EEA`. `NEW == CANDIDATE: YES` (identity, один файл).
- Graph profile (`graph.pbtxt`, diagnostic profile E, baseline `fea1a5f1`):
  - `MODEL_PATH: C:/llm/models/OpenVINO/Wondernutts/gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov` (на месте: 14.8GB `openvino_language_model.bin`, tokenizer/detokenizer, `chat_template.jinja`)
  - `DEVICE: GPU`, plugin `DYNAMIC_QUANTIZATION_GROUP_SIZE=0, PERFORMANCE_HINT=LATENCY, KV_CACHE_PRECISION=u8`
  - `max_num_seqs=1`, prefix caching on, `cache_size=0`, `pipeline_type=VLM_CB`
  - `chat_template_mode=MINJA`, `tool_parser=gemma4`, `reasoning_parser=gemma4`, `enable_tool_guided_generation=true`, `max_tokens_limit=65536`
- Флаги/шаблон/модель/DLL не менялись — менялся только бинарь (rebuild того же source).

## Launch Configuration

Exact launch (тот же exe+args+cwd, что в command.json; отклонение только в путях логов — evidence hygiene):

```powershell
$env:PATH = "C:\opt\openvino\runtime\bin\intel64\Release;C:\opt\openvino\runtime\3rdparty\tbb\bin;C:\opt\opencv_4.14.0\x64\vc16\bin;" + $env:PATH
Start-Process bazel-bin\src\ovms.exe --rest_port 8888 --port 9000 --config_path runtime\gemmamonster-ovms\config.json (cwd repo root)
```

(PATH-delta = тот же DLL-набор, что даёт `C:\opt\openvino\setupvars.bat`; setupvars как процесс не запускался.)

- PID `17456`, жив после старта; command line подтверждает exe; серверный лог: `tool_parser: gemma4`, `reasoning_parser: gemma4`, `gemma4 ... AVAILABLE`, `ServableManagerModule started`.
- Readiness: `GET /v3/models` → 200 `{"data":[{"id":"gemma4",...}]}`; `GET /v1/models` → 200, то же. (Наличие процесса readiness не считалось.)
- Лог сервера за сессию без `error|exception|dropped|failed` (проверено `Select-String`).

## Exact Requests

Харнесс: `C:\Users\testc\AppData\Local\Temp\opencode\gemma-acceptance\run_case.ps1` (общий контракт: `temperature=0`, `seed=42`, `max_tokens=512`, `tool_choice=auto`). Tool-контракты — из репо `tests/functional/constants/generative_ai.py:33-79` (`get_weather`/`get_pollutions`, `location` required, strict). Raw request/response: `case< X >_<mode>_run<N>.{request,response}.json` в той же папке. Валидатор: `validate.ps1`.

## Case A — single tool call (non-stream)

Request: `tools=[get_weather]`, `parallel_tool_calls=false`, "temperature in Berlin, Germany? Use the tool."

- HTTP 200, 2.2s, `finish_reason=tool_calls`, calls=1: `id=LcrsKK68K type=function name=get_weather args={"location":"Berlin, Germany"}`.
- Программная валидация: PASS. Regression control держится.

## Case B — multi-tools, one call (non-stream)

Request: `tools=[get_weather,get_pollutions]`, `parallel_tool_calls=false`, weather-only задача.

- HTTP 200, 1.9s, `finish_reason=tool_calls`, calls=1: `id=iHPfFGEcz name=get_weather args={"location":"Berlin, Germany"}`.
- Валидация: PASS. Выбор tool не регрессировал.

## Case C — parallel distinct tools (non-stream)

Request: `tools=[get_weather,get_pollutions]`, `parallel_tool_calls=true`, temperature AND pollution в Berlin, параллельно в одном шаге.

- HTTP 200, 2.7s, `finish_reason=tool_calls`, calls=2:
  - `id=pPNBxJWOI name=get_weather args={"location":"Berlin, Germany"}`
  - `id=mvulyushH name=get_pollutions args={"location":"Berlin, Germany"}`
- Валидация: PASS.

## Case D Non-Streaming — critical (5 runs)

Request: `tools=[get_weather]`, `parallel_tool_calls=true`, Berlin AND Munich, два параллельных вызова в одном шаге.

- run1: ids `kSMp3gV7Y` (Berlin) / `Yxvvtcxla` (Munich)
- run2: ids `c05zpa9YW` / `zsu4SLHz2`
- run3: ids `6rrgqdB5Q` / `wiIjVyolm`
- run4: ids `WNEJJTpW2` / `zLDZq5Y8d`
- run5: ids `jtN9ZcVI8` / `ZyWnpDHlU`
- Все: HTTP 200, ~1.8–2.3s, `finish_reason=tool_calls`, `tool_calls.length==2`, same `function.name=get_weather`, different IDs, different args, args — валидный JSON с `location`.
- `validate.ps1`: 5/5 PASS (проверены count, unique IDs, type==function, name, JSON args, same-name + different-IDs + different-args).

## Case D Streaming

Request: тот же контракт D, `stream=true`. HTTP 200, 935 bytes SSE:

- chunk1: `delta.role=assistant`
- chunk2: `tool_calls[{id=P5LJhLdYJ, index=0, name=get_weather, arguments={"location":"Berlin, Germany"}}]`
- chunk3: `tool_calls[{id=hmDtMPLic, index=1, name=get_weather, arguments={"location":"Munich, Germany"}}]`
- chunk4: `finish_reason=tool_calls`, затем `[DONE]`
- Доказано: независимые индексы 0/1, независимые IDs, arguments не смешиваются, второй call не присоединён к первому, дедупликации по имени нет, turn закрыт корректно. PASS.

## Repeatability

| run | HTTP | calls | same name | unique IDs | distinct args | result |
| --- | --- | --- | --------- | ---------- | ------------- | ------ |
| D non-stream 1 | 200 | 2 | yes | yes | Berlin/Munich | PASS |
| D non-stream 2 | 200 | 2 | yes | yes | Berlin/Munich | PASS |
| D non-stream 3 | 200 | 2 | yes | yes | Berlin/Munich | PASS |
| D non-stream 4 | 200 | 2 | yes | yes | Berlin/Munich | PASS |
| D non-stream 5 | 200 | 2 | yes | yes | Berlin/Munich | PASS |

Класс: PASS (устойчиво, не stochastic failure; seed=42 в контракте, honoured-статус сервером не проверен — см. Limitations).

## Memory Observation

- До запросов: WS `6457827328`, Private `16522170368`, Virtual `22424440832`.
- Пик (после 5 runs D + stream): WS `6862094336` (+~400MB), Private `16910880768`, процесс жив.
- `OOM: NO`, `process survived: YES`. (Грубое наблюдение, не benchmark.)

## Failure Autopsy

Не требуется — FAIL нет. Первый неправильный слой не наблюдался ни в одном case.

## Acceptance Matrix

| Case | stream | expected calls | same tool? | HTTP | parsed calls | valid JSON | unique IDs | result |
| ---- | -----: | -------------: | ---------: | ---: | -----------: | ---------: | ---------: | ------ |
| A single | false | 1 | N/A | 200 | 1 | yes | yes | PASS |
| B multi-tools/one call | false | 1 | N/A | 200 | 1 | yes | yes | PASS |
| C parallel distinct | false | >=2 | No | 200 | 2 | yes | yes | PASS |
| D repeated same-tool | false | 2 | Yes | 200 | 2 (x5 runs) | yes | yes | PASS |
| D repeated same-tool | true | 2 | Yes | 200 | 2 (index 0+1) | yes | yes | PASS |

## Final Verdict

**ACCEPTED** для candidate `9926F8B5...68EEA` на source `fde0762ba314dc5f6448726dfce7c533bad9a8a6`: все критерии §15 выполнены (provenance, binary==candidate, запуск новым binary, single/distinct без регрессий, repeated same-tool в обоих режимах, уникальные IDs, валидные arguments, без OOM, 5/5 устойчиво).

Causal оговорка (§18): в сессии нет before/after-сравнения (старый контент exe перезаписан rebuild'ом без backup), поэтому утверждение "именно `fde0762` починил" сильно только в связке с ранее зафиксированным failing evidence из gate12-расследований, а не из одного этого зелёного прогона. Сам по себе прогон доказывает: на этом бинаре поведение корректно и устойчиво.

## Handoff

```text
SOURCE_SHA: fde0762ba314dc5f6448726dfce7c533bad9a8a6
BINARY_SHA256: 9926F8B520704CCF429DEB67F4DFF7A76466A749A1AD1700750BEC0DED968EEA
RUNTIME_BINARY_SHA256: 9926F8B520704CCF429DEB67F4DFF7A76466A749A1AD1700750BEC0DED968EEA (same file)
MODEL: C:/llm/models/OpenVINO/Wondernutts/gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov (GPU, MINJA, gemma4 parsers, guided generation on)
LAUNCH_PROFILE: runtime/gemmamonster-ovms (rest 8888/grpc 9000, PID 17456, left running)

SINGLE_CALL: PASS
DISTINCT_PARALLEL_CALLS: PASS
REPEATED_SAME_TOOL_NONSTREAM: PASS 5/5
REPEATED_SAME_TOOL_STREAM: PASS
REPEATABILITY: PASS (deterministic across 5 runs)
OOM: NO

FIRST_BAD_STATE: none observed
ROOT_CAUSE: N/A (no failure); prior repeated-call defect addressed by fde0762 per source, behavior confirmed green on this binary
VERDICT: ACCEPTED

REPORT: .codesleuth/reports/20260910T060135Z-gemmamonster-fde0762-repeated-parallel-toolcall-acceptance.md
EVIDENCE: C:\Users\testc\AppData\Local\Temp\opencode\gemma-acceptance\ (requests/responses/logs/harness)
```

## Limitations

- Durable review/`provenance_state_*` недоступны в этом worktree (stale submodule gitdir) — `provenance: anon`, watermark не выдуман.
- `seed=42` отправлен, но honoured-статус сервером не верифицирован; генерация на практике детерминирована (5 одинаковых структур).
- Стриминг проверен 1 прогоном (контракт требует stream+nonstream — выполнено; x5 требовались только для non-stream).
- Сервер оставлен запущенным (PID 17456) для дальнейших проверок; останов не производился.
- Отчёт — acceptance evidence проекции, не SIB/EHA verdict; PASS относится только к этому exact SHA/binary.
