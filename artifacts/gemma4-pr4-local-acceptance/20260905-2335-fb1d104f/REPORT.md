GEMMAMONSTER GEMMA4 PR4 LOCAL ACCEPTANCE

SOURCE_HEAD:
fb1d104f5dccefa8ea770dc913d8cdedbf1642eb

PR_BASE:
0a537f08987a3df4c0254c1614162c06ac20b968

BINARY_SHA256:
3AF3838FFD2588BA0CADF60E3BE598C4CD80220F1BDDC4720686B443F4BFE739

BUILD:                   PASS
UNIT_TESTS:              FAIL
PARSER_REGRESSIONS:      PASS
GEMMA4_TOOL_STACK:       PASS
HARD_GENERATION:         PASS
STREAMING:               PASS
LATER_TURN_AGENT:        PASS
MULTILINE_BOUNDED:       PASS

NONE:                    PASS
AUTO:                    PASS
REQUIRED:                PASS
NAMED:                   PASS
NESTED_OBJECTS:          PASS
ARRAYS:                  PASS
QUOTING:                 PASS
PARALLEL_CALLS:          PASS
TOOL_ROUNDTRIP:          PASS

GPU_LONG_GENERATION_STABILITY:
FAIL

OVERALL:
NOT_ACCEPTED

# Why OVERALL is NOT_ACCEPTED

The mandatory Bazel target `//src/test/llm/generation_config:gemma4_generation_contract_test` cannot analyze on this HEAD:

```
target '//src:test_platform_utils' is not visible from target
'//src/test/llm/generation_config:gemma4_generation_contract_test'
```

`test_platform_utils` is a default-private `cc_library` in `src/BUILD`. The dedicated package added in this PR depends on it without a visibility grant. The same tests are not linked into `ovms_test.exe` (gtest ran 0 tests). That gate is FAIL. SKIP is not counted as PASS.

This is a test-BUILD wiring defect, not a runtime tool-calling regression. Fresh binary + parser gtests + the isolated Heretic matrix below are green. A visibility-only source fix would change HEAD and requires a new evidence run on the new SHA; this bundle is bound to `fb1d104f`.

# Environment

- Host: Windows 11 Home 10.0.26200, Intel Core Ultra 7 258V, Intel Arc 140V (16GB), 32 GB unified memory
- Toolchain: VS 2022 Build Tools at `C:\BuildTools`, MSVC 14.44.35207, cl 19.44.35228, Bazel 6.4.0, CMake 4.3.3, Python 3.12.10
- OpenVINO: 2026.4.0-22930-61afcb26271-releases/2026/4
- OpenVINO GenAI: 2026.4.0.0-3401-5f7f1278107
- Model: `Wondernutts/gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov`
- Local model path: `C:\llm\models\OpenVINO\Wondernutts\gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov`
- Fresh package: `C:\llm\ovms-gemma4-pr4-fb1d104f\ovms.exe` (22,734,848 bytes)
- Git: branch `fix/gemma4-rc1-reviewed-contracts`, merge-base `0a537f08`, descendant of predecessor, no commits after handoff SHA

# Exact commands

## Build

Working directory: `C:\git\model_server-gemma4-reviewed`

```
powershell -ExecutionPolicy Bypass -File C:\git\gemmamonster-acceptance\ovms\gemma4-diagnostic-pack\backports\ovms-2026.4-gemma4-tools\build-windows.ps1 `
  -ModelServerPath C:\git\model_server-gemma4-reviewed `
  -SkipApply `
  -SkipParserTests `
  -VisualStudioPath C:\BuildTools `
  -DeployTo C:\llm\ovms-gemma4-pr4-fb1d104f
```

This wrapper is the host-documented Windows path: it temporarily rewrites the pinned `VS_2022_BT` / `BAZEL_VC_FULL_VERSION` in `windows_build.bat` (this machine installs Build Tools at `C:\BuildTools`, not `Program Files (x86)`), then runs:

```
windows_build.bat opt --with_python --with_tests
windows_create_package.bat opt --with_python
```

and restores the original script bytes. `-SkipApply` because HEAD already contains the Gemma4 contracts.

- start: 2026-09-05T22:26:23+02:00
- end: 2026-09-05T23:22:06+02:00
- duration: 3342.8 s
- exit code: 0
- `ovms.exe --version`: `OpenVINO Model Server 2026.4.0.fb1d104f` / `--config=win_mp_on_py_on`
- logs: `artifacts/gemma4-pr4-local-acceptance/20260905-2335-fb1d104f/build/`

## Unit / parser

Working directory: `C:\git\model_server-gemma4-reviewed` after `windows_setupvars` / OpenVINO+OpenCV setupvars.

| Command | Exit | Duration | Result |
| --- | --- | --- | --- |
| `bazel --output_user_root=C:\opt test --config=win_mp_on_py_on --action_env OpenVINO_DIR=C:\opt/openvino/runtime/cmake --test_output=all --test_timeout=600 //src/test/llm/generation_config:gemma4_generation_contract_test` | 1 | 209.6 s | FAIL visibility |
| `ovms_test.exe --gtest_filter=Gemma4OutputParserTest.*` | 0 | 9.9 s | PASS 39/39 |
| `ovms_test.exe --gtest_filter=Gemma4ReviewedContractTest.*` | 0 | 10.4 s | PASS 6/6 |
| `ovms_test.exe --gtest_filter=HttpOpenAIHandlerParsingTest.*Tool*:...` | 0 | 22.9 s | PASS 34/34 |
| `ovms_test.exe --gtest_filter=Gemma4GenerationContractTest.*` | 0 | 0 s | SKIP 0 tests |

Parser coverage includes Gemma4 tool parser, guided JSON scanning, reasoningâ†’tool transition, streaming deltas, partial markers, nested JSON, quoted braces/commas/backslashes (`Gemma4ReviewedContractTest.GuidedJsonEveryByteSplitPreservesStringsAndTypes` and native quoting tests in `Gemma4OutputParserTest`).

## Runtime startup

```
C:\llm\ovms-gemma4-pr4-fb1d104f\ovms.exe `
  --config_path <diagnostic-pack runtime config> `
  --rest_port 8000 --rest_workers 1 `
  --log_level TRACE --verbose_response
```

Graph: `vlm-stable`, `device: GPU`, `chat_template_mode: JINJA`, `DYNAMIC_QUANTIZATION_GROUP_SIZE: 0`.

- start 23:35:44, AVAILABLE 23:36:22 (~37.5 s)
- `/v1/models`: `gemma4-26-heretic`
- auto-detected `tool_parser: gemma4`, `reasoning_parser: gemma4`
- server log: `runtime/server.log`

# Runtime matrix evidence

Isolated cases. Raw request/response under `runtime/requests` and `runtime/responses`. SSE under `runtime/streaming`. NovaClaw turns under `runtime/novaclaw`. Metrics: `metrics/runtime-metrics.csv`.

| Case | HTTP | wall s | finish | tokens | Result |
| --- | --- | ---: | --- | --- | --- |
| A none | 200 | 0.79 | stop | 2 | PASS content `4`, no tool_calls |
| B auto expected | 200 | 1.63 | tool_calls | 15 | PASS `get_weather` Berlin |
| B auto optional | 200 | 0.48 | stop | 2 | PASS `hello`, no tool |
| C required | 200 | 1.39 | tool_calls | 18 | PASS empty content, `get_weather` |
| D named | 200 | 1.39 | tool_calls | 23 | PASS forced `get_weather`, not `calculate` |
| E nested | 200 | 4.15 | tool_calls | 79 | PASS nested `event.when` / attendees |
| F arrays | 200 | 3.31 | tool_calls | 65 | PASS path/tag arrays |
| G quoting | 200 | 2.94 | tool_calls | 59 | PASS `run_command` JSON args |
| H parallel | 200 | 1.73 | tool_calls | 29 | PASS Berlin + Paris |
| I streaming | 200 | 0.87 | tool_calls | n/a | PASS name+args deltas, TTFT 0.63 s |
| J roundtrip | 200 | 1.41 | stop | 13 | PASS final content, no recall |
| K later-turn | 200 | 1.87 | tool_calls | 26 | PASS TURN2 `read_file`, empty prose |
| L bounded multiline | 200 | 28.85 | tool_calls | 582 | PASS `write_file` 1169 B body, max_tokens=2048 |
| failclosed required+json | 400 | 0.02 | n/a | n/a | PASS API error, no generation |
| failclosed auto+json | 400 | 0.02 | n/a | n/a | optional combo also rejected; not a hard-choice miss |
| GPU_LONG_GENERATION_STABILITY | 200 | 109.43 | length | 2048 | FAIL truncation / invalid JSON args |

Fail-closed error body:

```
Gemma4 response_format cannot be combined with active tool generation constraints
```

No unconstrained text generation started.

# Hard generation

Semantic prefix gate, not token-id 48.

- `required`: TRACE `OVMSTextStreamer` decoded starts with `<|tool_call>call:get_weather{...`; first token id **48** (diagnostic).
- `named`: decoded also starts with `<|tool_call>call:get_weather{...`; first token id **236820** (fragmented tokenizer path). This is PASS under the RC1 semantic rule.
- `none`: decoded `4<turn|>`, first token 236812, not a tool start.

No `Ð¡ÐµÐ¹Ñ‡Ð°Ñ Ð¿Ñ€Ð¾Ð²ÐµÑ€ÑŽ...` / promise prose on required, named, or later-turn.

# Metrics

See `metrics/runtime-metrics.csv` and `metrics/host-metrics.csv`.

Host polling ~1 s via `Get-Counter`. GPU counter sets existed (`GPU Engine`, `GPU Adapter Memory`, `GPU Process Memory`, ...). Wildcard samples for Engine Utilization stayed 0 and dedicated memory stayed 0; those cooked values are **not** treated as Arc busy%. Process working set during load peaked at ~17.8 GB; system memory used peaked near 32 GB during model bring-up.

Streaming TTFT: 0.628 s. Bounded write ~20.2 completion tok/s. Stress 2048 completion tokens in 109 s (~18.7 tok/s) then `finish_reason=length`.

# GPU_LONG_GENERATION_STABILITY

Separate from `GEMMA4_TOOL_STACK`. 4600 B body, `max_tokens=2048`, `write_file` / `required`.

- FAIL: `FINISH_length` + `ARGUMENTS_INVALID_JSON` (truncated generation, not a parser prose miss).
- No `CL_OUT_OF_RESOURCES` in this run's server log.
- `/v1/models` still listed `gemma4-26-heretic` after the case.
- Following trivial `tool_choice=none` inference returned `pong` / `finish_reason=stop`. Server restart was **not** required.
- This matches the known long-generation ceiling, not a new parser regression.

# Failures / skips / restarts

Failing:
- `//src/test/llm/generation_config:gemma4_generation_contract_test` (visibility)
- `GPU_LONG_GENERATION_STABILITY` (truncation at 2048 tokens)

Skipped:
- `Gemma4GenerationContractTest.*` via `ovms_test.exe` (0 tests)
- `bazel test --nocheck_visibility` not used as the acceptance command (would not make the default target PASS)

Restarts: none after server start. GPU/driver: no CL_OUT in this session.

# Known limitations

- Dedicated generation-contract Bazel package is unwired (visibility).
- GPU Engine `% Utilization` wildcard samples are not a trustworthy Arc 140V busy metric on this counter set.
- TRACE `OVMSTextStreamer` regex extractor captured extra following log lines when the decode contained quotes; raw TRACE lines in `runtime/server.log` are authoritative.
- `rest_workers` log line showed 2 despite `--rest_workers 1`; not material to the matrix.

# Paths

- Evidence dir: `artifacts/gemma4-pr4-local-acceptance/20260905-2335-fb1d104f/`
- Report: `docs/superpowers/reports/2026-09-05-gemma4-pr4-local-acceptance.md`
- Bundle: `artifacts/gemma4-pr4-local-acceptance/gemma4-pr4-local-acceptance-fb1d104f-20260905-2335.zip`
- Binary SHA256: `3AF3838FFD2588BA0CADF60E3BE598C4CD80220F1BDDC4720686B443F4BFE739`
- Bundle SHA256: 41A5019F2A98C38D8B9C7105D48377C4AE301B394350CFC157AA54F1871C6058 (220311 bytes)
