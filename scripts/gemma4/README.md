# GEMMAMONSTER Gemma4 operator guide

This directory is the operator entry point for the Gemma4 reliability overlay on OVMS. It covers the normal Windows/Intel Arc workflow from a source checkout and the standalone Windows package produced from an accepted build.

For implementation history, forward-port rules and hardening rationale, use the maintainer documents linked at the end. This README deliberately stays operational.

## Current runtime contract: Profile E

Profile **E** is the primary target-machine runtime profile. Its machine-readable source of truth is `runtime/gemmamonster-ovms-E/profile.json`.

Profile E requests:

- device `GPU`
- pipeline `VLM_CB`
- `max_num_seqs: 1`
- `DYNAMIC_QUANTIZATION_GROUP_SIZE: 0`
- `KV_CACHE_PRECISION: u8`
- prefix caching enabled
- Jinja chat-template processing
- `max_tokens_limit: 65536`

`cache_size` is intentionally **unset**. The frozen evidence does not establish the exact working E value, so neither launcher may silently borrow B2's `0` or C's `8`.

The `KV_CACHE_PRECISION=u8` value above is the requested Profile E plugin configuration. When validating a new OpenVINO/OpenVINO GenAI dependency set, inspect the compiled-model runtime log as well; do not infer the effective backend precision only from the profile name.

`Stable` and `PrefixCache` are diagnostic comparison profiles in `launch-gemma4-candidate.ps1`. They are not aliases for Profile E.

---

## Workflow A: build, launch and test from the source tree

Run these commands from the repository root in PowerShell 7.

### 1. Checkout the integration branch and run the static audit

```powershell
git fetch origin
git switch integration/ovms-2026.5-forward-port
git pull --ff-only origin integration/ovms-2026.5-forward-port
git rev-parse HEAD
git status --short

pwsh -File .\scripts\gemma4\audit-forward-port.ps1 `
  -OutputPath .\tmp\gemma4-audit.json
```

Do not proceed to build with a static-audit `FAIL`. Any remaining warning must be understood and recorded in acceptance evidence.

### 2. Build the local candidate

```powershell
pwsh -File .\scripts\gemma4\build-local-candidate.ps1 `
  -ShortRoot g5 `
  -Label 2026.5-candidate
```

Useful build switches:

- `-SkipDependencies` reuses the already installed pinned dependency tree.
- `-ExpungeDependencies` performs a clean dependency extraction.
- Python/Jinja support and tests are enabled by default.

The build wrapper records source HEAD, dependency provenance and the `ovms.exe` SHA256 under:

```text
tmp\gemmamonster-acceptance\2026.5-candidate\
```

A successful build is still only **COMPILED**. It is not runtime-accepted yet.

### 3. Prepare the Google-template model overlay

Prepare the overlay once and reuse the same overlay for comparable runs:

```powershell
pwsh -File .\scripts\gemma4\prepare-google-template-overlay.ps1 `
  -SourceModelPath 'C:\llm\models\OpenVINO\Wondernutts\gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov' `
  -OverlayPath 'C:\llm\models\OpenVINO\gemma4-google-template-overlay'
```

The source model is treated as immutable. The overlay replaces only the chat-template authority and writes `gemma4-template-provenance.json` beside the model files.

Do not recreate the overlay between A/B measurements unless changing the template is the experiment.

### 4. Launch Profile E from the source tree

```powershell
pwsh -File .\scripts\gemma4\launch-gemma4-candidate.ps1 `
  -OvmsExe '.\bazel-bin\src\ovms.exe' `
  -ModelPath 'C:\llm\models\OpenVINO\gemma4-google-template-overlay' `
  -ModelName 'gemma4-26-heretic' `
  -ShortRoot g5 `
  -Label '2026.5-candidate' `
  -Profile E `
  -ChatTemplateMode JINJA `
  -RestPort 8000 `
  -GrpcPort 9000
```

The launcher refuses to kill a process already using either requested port. On success it waits for `/v2/health/ready` and prints `OVMS READY` with the PID.

Generated source-tree runtime files are placed under:

```text
tmp\gemmamonster-ovms\2026.5-candidate-e\
```

The directory contains the generated `config.json`, `graph.pbtxt`, `launch.json` and `ovms.log`.

### 5. Run acceptance

Open a second PowerShell session while OVMS remains running.

Smoke acceptance:

```powershell
pwsh -File .\scripts\gemma4\run-candidate-acceptance.ps1 `
  -OvmsExe '.\bazel-bin\src\ovms.exe' `
  -ModelName 'gemma4-26-heretic' `
  -BaseUrl 'http://127.0.0.1:8000' `
  -Label '2026.5-candidate' `
  -Reliability Smoke `
  -TemplateProvenancePath 'C:\llm\models\OpenVINO\gemma4-google-template-overlay\gemma4-template-provenance.json'
```

The runner first repeats the static audit, then executes chained tool calls in `named`, `required` and `auto` modes and runs the grounded reliability matrix.

Before promotion, repeat with:

```powershell
-Reliability Full
```

Acceptance requires the worktree HEAD to exactly match the commit SHA being accepted. Evidence is written under:

```text
tmp\gemmamonster-acceptance\<label>-<sha8>\
```

The final machine-readable verdict is `candidate-acceptance.json`.

### 6. Run the frozen legacy performance prompts

Run performance comparison only after correctness acceptance.

```powershell
New-Item -ItemType Directory -Path .\tmp\gemmamonster-bench -Force | Out-Null

pwsh -File .\scripts\gemma4\benchmark-legacy-prompts.ps1 `
  -BaseUrl 'http://127.0.0.1:8000/v3' `
  -Model 'gemma4-26-heretic' `
  -TimeoutSec 1200 |
  Tee-Object -FilePath .\tmp\gemmamonster-bench\legacy-prompts.json
```

The script is the frozen reproducibility source for these cases:

- one 16-token warmup
- three 128-token trials with seeds `101`, `102`, `103`
- one 512-token GPU prompt
- one 1024-token long prompt
- one 2048-token long prompt

It reports wall elapsed time, prompt/completion token counts, completion tokens per second and finish reason. Keep the literal prompts and generation settings unchanged when comparing candidates.

### 7. Build the standalone Windows package

Choose a new output directory. The packager deliberately refuses to overwrite an existing `OutputRoot`.

```powershell
pwsh -File .\scripts\gemma4\package-standalone-runtime.ps1 `
  -OutputRoot 'C:\llm\packages\gemmamonster-2026.5' `
  -DependencyRootName g5
```

The command uses the standard `windows_create_package.bat` flow with Python enabled, then adds the Gemma4 Profile E runtime assets.

Expected output layout:

```text
C:\llm\packages\gemmamonster-2026.5\
  ovms\
    ovms.exe
    python\
    gemma4\
      README.md
      Start-Gemma4.ps1
      PACKAGE-PROVENANCE.json
      profile-E\
        profile.json
        README.md
    SHA256SUMS
  ovms-gemma4-2026.5-<sha8>-windows.zip
```

Model weights are **not** included. The runtime model path is supplied externally when starting the package.

`SHA256SUMS` covers the files inside the package, including the Gemma4 operator assets. `PACKAGE-PROVENANCE.json` records the exact Git SHA and `ovms.exe` SHA256 used for the package.

---

## Workflow B: run an unpacked standalone package

This path does not require the source-tree launcher. Unpack the ZIP, change into the `ovms` package directory, and point the packaged launcher at the external model/overlay directory.

```powershell
cd C:\llm\packages\gemmamonster-2026.5\ovms

pwsh -File .\gemma4\Start-Gemma4.ps1 `
  -ModelPath 'C:\llm\models\OpenVINO\gemma4-google-template-overlay'
```

Defaults are:

- model name: `gemma4-26-heretic`
- REST port: `8000`
- gRPC port: `9000`
- readiness timeout: `300` seconds
- runtime profile: Profile E

Optional overrides:

```powershell
pwsh -File .\gemma4\Start-Gemma4.ps1 `
  -ModelPath 'C:\llm\models\OpenVINO\gemma4-google-template-overlay' `
  -ModelName 'gemma4-26-heretic' `
  -RestPort 8000 `
  -GrpcPort 9000 `
  -ReadinessTimeoutSeconds 300
```

Use `-Wait` if the calling shell should remain attached until the OVMS process exits.

Without `-Wait`, the launcher returns the PowerShell process object and prints the PID. Stop that exact process explicitly when required:

```powershell
Stop-Process -Id <PID>
```

The standalone launcher does not kill an existing process to free a port.

### Standalone runtime files and logs

The packaged launcher generates machine-local runtime state under:

```text
%LOCALAPPDATA%\OVMS\gemma4\<ModelName>-profile-e\
```

The important files are:

```text
config.json
graph.pbtxt
ovms.log
```

Readiness can be checked independently with:

```powershell
Invoke-WebRequest `
  -Uri 'http://127.0.0.1:8000/v2/health/ready' `
  -UseBasicParsing
```

For parser/template/runtime diagnosis, inspect `ovms.log` and confirm the loaded chat template, auto-detected `gemma4` tool/reasoning parsers and the effective compiled-device properties rather than relying only on launcher labels.

---

## Verify a standalone package from a source checkout

The repository includes the Windows package verifier:

```powershell
pwsh -File .\tests\windows\gemma4_standalone_package_test.ps1 `
  -PackageRoot 'C:\llm\packages\gemmamonster-2026.5\ovms' `
  -ExpectedGitSha (git rev-parse HEAD)
```

It checks the required OVMS runtime files, Profile E assets, provenance, every `SHA256SUMS` entry, `ovms.exe --version` and `ovms.exe --help`.

Live acceptance can also target a packaged `ovms.exe`, but `run-candidate-acceptance.ps1` is intentionally repository-backed: its `RepoRoot` and exact Git HEAD must correspond to the binary being accepted.

---

## A/B comparison rules

When comparing OVMS revisions, keep these constant unless the experiment explicitly changes one of them:

- model weights and IR
- Google-template overlay and its exact template provenance
- Profile E
- ports and API path
- tool catalog
- request prompts and sampling settings

Do not compare Profile E on one binary against `Stable`, `PrefixCache`, B2 or C on another and label the result an OVMS-version comparison.

Correctness precedes throughput. A faster build that regresses chained tool calling or grounded reliability is not a promotion candidate.

---

## Operator troubleshooting

### Port already in use

Both launchers refuse to terminate unrelated processes. Identify the listener before choosing whether to stop it or use another port:

```powershell
Get-NetTCPConnection -State Listen -LocalPort 8000,9000 |
  Select-Object LocalAddress,LocalPort,OwningProcess
```

### Readiness timeout or early OVMS exit

Inspect the log path printed by the launcher. Source-tree runs use the generated `tmp\gemmamonster-ovms\...` directory. Standalone runs use `%LOCALAPPDATA%\OVMS\gemma4\...`.

### Jinja/Python problems

The source-tree launcher uses the machine Python environment configured for the build. The standalone launcher prepends the packaged Python runtime and, when present, sets `PYTHONHOME`/`PYTHONPATH` to the package-local Python tree.

### Acceptance refuses the commit SHA

`run-candidate-acceptance.ps1` requires the requested commit to resolve exactly and requires the current worktree HEAD to equal it. Checkout the exact package/build commit instead of overriding provenance.

### Package output already exists

This is intentional overwrite protection. Choose a fresh `OutputRoot`; do not reuse a previous package directory as mutable release state.

---

## Maintainer and design references

Use these documents when the operator procedure is not enough:

- `docs/superpowers/runbooks/2026.5-local-build-test.md` - detailed source build, Profile E launch and local acceptance procedure.
- `docs/superpowers/runbooks/gemma4-upstream-forward-port.md` - authority for carrying the reliability overlay onto a future OVMS upstream head.
- `runtime/gemmamonster-ovms-E/README.md` and `profile.json` - Profile E contract and rationale.
- `docs/superpowers/plans/2026-09-09-gemma4-2026.5-standalone-hardening.md` - standalone hardening and packaging implementation plan.

For normal operation, start here rather than reconstructing the command sequence from those documents.