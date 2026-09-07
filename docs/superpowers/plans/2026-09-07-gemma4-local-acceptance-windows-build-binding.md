# Gemma4 Local Acceptance Windows Build Binding

This file is a mandatory execution binding for `docs/superpowers/plans/2026-09-07-gemma4-local-acceptance-integration.md`, Task 6 and Task 8. It removes ambiguity around the Windows build environment used by the existing Gemma4 OVMS workflow.

## Working directory

Run the build helper from the root of the checked-out `DassaultFalconKing/model_server` worktree that is detached at the exact `TEST_SHA` produced by Task 7.

Before the build:

```powershell
$env:PYTHONHOME="C:\opt\Python312"
```

Do **not** source:

```powershell
C:\llm\ovms\setupvars.ps1
```

That environment script is excluded from this acceptance path because prior local build work explicitly avoided it.

## Development build command

For iterative local build/debug work before the final acceptance run:

```powershell
.\windows_build_fast.ps1 -Mode Dev -WithPython $true -SkipFastTests -OpenVinoDir "C:/opt/openvino/runtime/cmake"
```

`-SkipFastTests` is development-only. A Dev build is never sufficient for `LOCAL_ACCEPTED`.

## Final verification build command

The G1 build used by the actual acceptance run is:

```powershell
.\windows_build_fast.ps1 -Mode Verify -WithPython $true -OpenVinoDir "C:/opt/openvino/runtime/cmake"
```

The runner must capture this exact command, exit code, stdout and stderr in the current provenance-bound run directory.

## OVMS executable

The expected repository-relative executable produced by the verified Windows build is:

```powershell
.\bazel-bin\src\ovms.exe
```

Before hashing or launching it, the acceptance runner must resolve the path and verify it exists:

```powershell
$OvmsExe = (Resolve-Path ".\bazel-bin\src\ovms.exe").Path
if (-not (Test-Path $OvmsExe -PathType Leaf)) { throw "Verified build did not produce ovms.exe" }
$BinaryHash = (Get-FileHash -Algorithm SHA256 $OvmsExe).Hash.ToLowerInvariant()
```

The binary SHA256 is part of the final acceptance identity and must appear in `summary.json`.

## Required Task 6 substitution

Where the main implementation plan says to invoke the repository's existing Windows build entry point, use the **Final verification build command** above for the actual G1 acceptance run. Do not substitute an older `windows_build.bat`, an already installed `C:\llm\ovms\ovms.exe`, or a binary from another checkout.

The locally installed OVMS binary may be used only as historical/reference evidence. The binary tested for `LOCAL_ACCEPTED` must be the one produced from the detached exact `TEST_SHA` by this build contract.
