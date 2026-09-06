# Gemma4 reliability / grounded-facts campaign runbook

Snapshot freeze of an in-progress test session. Production code is unchanged.
Do not merge this branch. Do not treat incomplete cells as final supervisor
verdicts.

## Authority

| Item | Value |
|---|---|
| Snapshot branch | `test/gemma4-reliability-snapshot` |
| Live dirty tree (do not mix) | `C:\git\model_server-gemma4-clean` on `test/gemma4-reliability-grounded-facts` |
| Snapshot worktree | `C:\git\model_server-gemma4-reliability-snapshot` |
| Test HEAD when campaign started | `74ea54e19825812fac6f5dbf7f9e24051a75eba6` |
| Production SHA under test | `908bc8b7e3bdd24ddd5eb9b27bbe15bcffb00703` |
| Binary | `C:\git\g4-final-review\bazel-bin\src\ovms.exe` |
| Binary stamp | `OpenVINO Model Server 2026.4.0.908bc8b7` |
| Binary SHA256 | `83938cf36ef70a53e024e467f31b4a8b841e66815b93292457ae1b1472bd105b` |
| Device | Intel OpenVINO GPU (`CPU, GPU, NPU`). Not NVIDIA. Do not call `nvidia-smi`. |

## Do not

- Change parser / generation-config / chat-template / servable / models.
- Touch `fix/gemma4-final-toolcalling-review` or `main`.
- Use binary `b4b183d6` or REST `:8000`.
- Source `C:\llm\ovms\setupvars.ps1` (it sets `PYTHONHOME=C:\llm\ovms\python` and OVMS dies with `No module named encodings`).
- Run Bazel compiles in parallel with the live 26B server. That previously killed/hung OVMS.

## Working OVMS launch env

```powershell
$env:PYTHONHOME = "C:\opt\Python312"
$env:PYTHONPATH = "C:\llm\ovms\python;C:\opt\Python312\Lib\site-packages"
$env:PATH = "C:\opt\Python312;C:\opt\Python312\Scripts;C:\llm\ovms;C:\llm\ovms\python;C:\opt\openvino\runtime\bin\intel64\Release;C:\opt\openvino\runtime\3rdparty\tbb\bin;C:\opt\opencv_4.14.0\x64\vc17\bin;C:\git\g4-final-review\bazel-bin\src;C:\WINDOWS\system32;C:\WINDOWS"

Set-Location C:\git\gemmamonster-acceptance\ovms\gemma4-diagnostic-pack
.\launch.ps1 `
  -OvmsExe C:\git\g4-final-review\bazel-bin\src\ovms.exe `
  -ModelPath C:\llm\models\OpenVINO\Wondernutts\gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov `
  -ModelName gemma4-26-heretic `
  -Profile vlm-stable `
  -RestPort 18000 `
  -ChatTemplateMode JINJA
```

Ready when `http://127.0.0.1:18000/v1/config` shows `gemma4-26-heretic` `AVAILABLE`.
Healthy loaded process paged memory is ~16 GB. A 13 MB `ovms.exe` is not a loaded model.
Python for the harness: `C:\opt\Python312\python.exe` with `PYTHONHOME=C:\opt\Python312`.

Graph: `vlm-stable`, JINJA, parser auto-detected `gemma4`. Graph does **not** set
`enable_tool_guided_generation` (H1 for that flag is code-contract only).
Model `generation_config.json`: `temperature=1.0`, `do_sample=true`, `top_k=64`, `top_p=0.95` (cell A3).

## Resume the live campaign

Harness is resume-safe (default `--resume`). Run from `C:\git\model_server-gemma4-clean`
against the already-written `ab-evidence/reliability-campaign/trials.jsonl`.
Do not start a second harness against the same jsonl.

```powershell
Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
$env:PYTHONHOME = "C:\opt\Python312"
Set-Location C:\git\model_server-gemma4-clean
C:\opt\Python312\python.exe ab-evidence\reliability_grounded_harness.py `
  --base-url http://127.0.0.1:18000 `
  --model gemma4-26-heretic `
  --binary C:\git\g4-final-review\bazel-bin\src\ovms.exe `
  --git-sha 74ea54e19825812fac6f5dbf7f9e24051a75eba6 `
  --production-sha 908bc8b7e3bdd24ddd5eb9b27bbe15bcffb00703 `
  --parser-name gemma4 `
  --chat-template-mode JINJA `
  --out-dir ab-evidence\reliability-campaign `
  --campaign all
```

After completion: `--campaign summarize`.

## Snapshot counts (frozen at commit time)

See `ab-evidence/reliability-campaign/snapshot-summary.json`. At freeze: **245 trials**.
Last trial: `thinking_off_t09_s42-005` PASS.

| Cell | N | Result at freeze |
|---|---:|---|
| named t=0 seed=42 | 30 | 30 PASS |
| required t=0 seed=42 | 50 | 50 PASS |
| auto A1 t=0 seed=42 | 30 | 30 G invented sha256 |
| auto A2 t=0 seed omitted | 20 | 20 G |
| auto A3 model default | 20 | 2 PASS / 18 G |
| auto A4 t=0.9 seed=42 | 15 | 15 PASS |
| auto A5 t=0.9 seed omitted | 15 | 1 PASS / 13 G / 1 truncated |
| thinking off t=0 seed=42 | 30 | 30 G (same as A1) |
| thinking on t=0 seed=42 | 30 | 1 PASS / 29 G |
| thinking off t=0.9 seed=42 | 5/20 | 5 PASS so far |
| thinking on t=0.9 | 0/20 | not started |
| Campaign B | 0/36 | not started |

Primary failure in `auto` so far is **G_UNGROUNDED_VALUE_INVENTED** (often empty-file
hash `e3b0c44…` in `sha256`), not wrong-tool / parser-reject / grounded `commit_sha`
corruption. Named/required second-turn exact `commit_sha` has been 80/80 PASS.

Still incomplete: rest of thinking 0.9, Campaign B, Bazel code-contract run,
supervisor report with H1–H4 verdicts.

## Code-contract tests (written, not executed in this freeze)

Set tokenizer (repo fixture is missing; without it parser tests fail at init):

```powershell
$env:GEMMA4_TOKENIZER_PATH = "C:\llm\models\OpenVINO\Wondernutts\gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov"
$env:BAZEL_VS = "C:\BuildTools"
$env:PATH = "C:\opt;C:\opt\msys64\usr\bin;" + $env:PATH
```

Do **not** pass the full user PATH as `--test_env=PATH` (Bazel then analyzes 0 test
targets). Fast loop: `.\windows_build_fast.ps1 -Mode Dev -SkipFastTests:$false`.
Adapter tests live in `//src:ovms_test`, not the fast loop.

Added/extended tests:

- `src/test/llm/generation_config/gemma4_generation_contract_test.cpp`
- `src/test/llm/gemma4_fast/gemma4_parser_contract_test.cpp`
- `src/test/llm/chat_template_adapter_test.cpp`

## Evidence layout

- `ab-evidence/reliability_grounded_harness.py`
- `ab-evidence/grounded-facts-fixtures.json`
- `ab-evidence/grounded-facts-catalog.json`
- `ab-evidence/reliability-campaign/trials.jsonl`
- `ab-evidence/reliability-campaign/raw/<trial_id>/trial.json`
- `ab-evidence/reliability-campaign/provenance.json`
- `ab-evidence/reliability-campaign/snapshot-summary.json`
