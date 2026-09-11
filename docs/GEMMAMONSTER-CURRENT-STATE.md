# Gemmamonster current state

This file is the canonical human-readable state index for the active Gemmamonster acceptance track.

Updated: 2026-09-11 (Europe/Berlin, CEST)

Canonical snapshot ref for this record:

`state/gemmamonster-current-2026-09-11-env-preflight`

Previous snapshot:

`state/gemmamonster-current-2026-09-11`

The snapshot ref, rather than a self-referential SHA written into this file, is the immutable-by-convention anchor for this state.

## Canonical published baseline

- Repository: `DassaultFalconKing/gemmamonster_model_server_OVMS`
- Published main predecessor before this state-record update: `2ed8aa624a5182f1188c864160d7715d6163ef59`
- Frozen 2026.4 known-good branch: `freeze/gemmamonster-2026.4-known-good`
- Frozen known-good branch HEAD: `c48366fee1f10cdf6b5fe3c181522ed0c58fc9fd`
- Proven known-good source SHA: `9a1626260614f68a6282b6799842d5152f0dcdff`
- Proven runtime pipeline: `VLM_CB`
- Known-good runtime profile: `maintainer-rc2`
- Known-good candidate: `9a162626-maintainer-rc2-gemma4-stable-rc2-lean-20260910T235114Z`
- Known-good `ovms.exe` SHA256: `E7D8024F4F385B8DA5051C343DA3ACE0FBEF65813767EFB74C7FCCFFEE80CB0A`
- Known-good status: `KNOWN_GOOD_TOOL_CALLING`

## Active local acceptance candidate

The active unified candidate is currently local-only and is NOT yet a remote canonical branch.

- Local worktree: `C:\git\gemmamonster-2026.4-unified-20260911`
- Local branch: `integration/gemmamonster-2026.4-unified-20260911`
- Last reported local candidate HEAD: `82a8a4ec7...`
- Earlier uncommitted composition anchor: `202d5e898d86af6dffd5e53fdc4e875f9de4ebed`
- Donor for GPU containment / build provenance work: `a7ab15f01a9ec7fd6579259c13fecee19c448863`

Until the local unified branch is pushed, this document records its identity but does not pretend it is remotely reproducible.

## Active remote working lines

| Role | Branch | HEAD | Last activity (CEST) | Meaning |
|---|---|---|---|---|
| Acceptance/evidence | `OVMS-Gemmamonster-acceptance-track` | `068e02c69b411b05800683340f43d733e9e08256` | 2026-09-11 06:00:34 | Tab-loop, repeated same-tool and acceptance evidence |
| Published stable baseline predecessor | `main` | `2ed8aa624a5182f1188c864160d7715d6163ef59` | 2026-09-11 04:09:38 | Published 2026.4 known-good documentation and provenance before this state-record update |
| 2026.4 refit predecessor | `integration/gemmamonster-2026.4-latest-refit` | `16df6acd96efea26bfa3d5df8f0c47b71c332b15` | 2026-09-11 01:18:26 | Last published 2026.4 refit/integration line |
| GPU containment donor | `fix/gemma4-gpu-fault-containment-sketch` | `a7ab15f01a9ec7fd6579259c13fecee19c448863` | 2026-09-11 05:39:13 | GPU fault classification/quarantine and validation donor |
| GPU containment contracts | `fix/gemma4-gpu-fault-containment-contracts` | `4e2e71a0b1dbfae453f75ae069ef424248c9740a` | 2026-09-11 04:42:12 | Contract/doc continuation; aliases share this HEAD |
| 2026.5 protocol donor | `integration/gemma4-protocol-hardening-2026.5` | `5d995cfafdb2ec90578678aa15714dedebc843b8` | 2026-09-09 18:57:45 | Parser/generator/streamer/protocol donor line |
| 2026.5 forward-port donor | `integration/ovms-2026.5-forward-port` | `ad19fc6d3934b5255be34059b07e52e0276e7168` | 2026-09-09 14:53:13 | Previous full 2026.5 migration/reference line |
| Evidence-only orphan | `Testrun_2026-09-11-gemmamonster-frankenstein-c5115ba` | `60494feae321811e356b9231b1030419e3b2a01a` | 2026-09-11 10:55:57 | Evidence only, not product lineage |
| State snapshot | `state/gemmamonster-current-2026-09-11-env-preflight` | resolve ref | 2026-09-11 | Current state plus mandatory sanitized environment gate |

## Current acceptance facts

- Canonical accepted pipeline remains `VLM_CB`.
- Do not switch the canonical acceptance track to `LM_CB` merely to bypass a GPU fault.
- A current candidate run hit `GPU_CONTEXT_FATAL` / `CL_OUT_OF_RESOURCES` and quarantined the executor while the process and `/v3/models` remained alive.
- That event is treated as a runtime/build regression candidate relative to the frozen known-good VLM_CB path, not as proof that VLM_CB is wrong.
- Repeating inference on a quarantined executor is invalid acceptance evidence.
- The next diagnostic priority is controlled A/B of exact old known-good package versus current candidate on the same host, followed by package and loaded-module provenance comparison if old passes and current fails.

## XGrammar state

- Version: `v0.2.6`
- Reported source SHA: `bc09a30e...`
- `max_whitespace_cnt=2`
- This is a separate guided-generation gate and must not be blamed for GPU `CL_OUT_OF_RESOURCES` without direct evidence.

## Mandatory environment pre-flight

Before any Gemmamonster dependency install, build, test, package, or runtime acceptance work, run:

```powershell
.\scripts\gemmamonster\Enter-GemmamonsterEnv.ps1
```

Run it in the same PowerShell process that will perform the work. Do not launch it in a disposable `powershell.exe -File ...` child process and then continue in another shell.

For build/test/package work after dependencies have already been bootstrapped, require the canonical RC2 runtime root as well:

```powershell
.\scripts\gemmamonster\Enter-GemmamonsterEnv.ps1 -RequireRuntimeRoot
```

The pre-flight is fail-closed and deliberately ordered:

1. **SANITIZE** process-scope selectors from prior OpenVINO/GenAI/Gemmamonster/Bazel/Python/Conda/venv work.
2. Remove stale OpenVINO, packaged OVMS, candidate, old `C:\g54*`, Python and MSYS entries from the inherited `PATH` while preserving unrelated system/tool paths.
3. Assert the stale build/runtime selectors are actually gone.
4. **INITIALIZE** the exact `maintainer-rc2` toolchain and dependency pins.
5. **VERIFY** active Bazel/Python versions, source identity, `versions.mk` authority, canonical paths, and optional runtime-root presence.
6. Proceed only when the script reports `ENV_PREFLIGHT = PASS`.

The script changes only the current process environment. It must not mutate User or Machine environment state. A new shell must run the pre-flight again.

Canonical pre-flight authority:

- Bazel `6.1.1`
- Python `3.12.10`
- MSVC Build Tools root `C:\BuildTools`, toolset `14.44.35207`
- short/runtime root `C:\g54r2`
- OpenVINO `227c33757d1ef95d4da506d00686f923fdd2a535`
- GenAI `7ea2546852a382cd16bd22dea0cfad2db70ed744`
- Tokenizers `a04accf6282d9b304214b492694b18c3979f667a`
- binary runtime line `2026.4.0.0rc2`

If the environment gate fails, do not build, test, package, or run acceptance until the mismatch is resolved. Environment provenance is part of build provenance.

## Branch policy

For future work:

1. Treat this document as the starting state index.
2. Run the mandatory sanitized environment pre-flight before any build/test/runtime work.
3. Prefer one active integration branch plus narrowly-scoped donor/evidence branches.
4. Do not create another integration branch merely to record state.
5. When the local unified branch is pushed, update the next dated state record with its exact full SHA and remote branch name.
6. Never call an uncommitted working tree a reproducible HEAD.
7. Record package SHA256, dependency pins, pipeline type, runtime profile, and acceptance verdict for every promoted candidate.
8. Evidence-only branches must remain explicitly marked as non-product lineage.
9. Do not move historical state snapshot refs after finalization; create a new dated or suffixed state snapshot when the canonical state materially changes.

## Promotion rule

A candidate may replace the frozen known-good only after all of the following are true:

- mandatory environment pre-flight passes in the same process that performs the build/acceptance work;
- immutable source SHA exists on remote;
- package/provenance contracts pass;
- exact OpenVINO / GenAI / Tokenizers / XGrammar pins are recorded;
- VLM_CB starts successfully;
- tiny generation passes without GPU quarantine;
- forced single tool call passes;
- tool-result continuation passes;
- streaming acceptance passes;
- the final accepted binary/package hashes are recorded.
