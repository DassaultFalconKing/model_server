# Gemma4 Windows fast-build workflow

`windows_build.bat` is the historical Jenkins/release-oriented entry point. It is intentionally still available, but it is too broad for Gemma4 parser/generator iteration: `--with_tests` builds the monolithic `//src:ovms_test` plus OVMS and eSpeak targets.

For local Gemma4 development use `windows_build_fast.ps1`.

## Dev loop

```powershell
.\windows_build_fast.ps1 -Mode Dev
```

This performs:

1. standalone Gemma4 generation-contract tests;
2. standalone Gemma4 parser-contract tests;
3. incremental `//src:ovms` build.

It does **not** build the monolithic `//src:ovms_test`, eSpeak packaging targets or the final distribution.

Default shared caches:

```text
C:\opt\bazel-disk-cache\win_mp_on_py_on
C:\opt\bazel-repository-cache
```

Because these are outside a repository checkout, multiple worktrees/checkouts can reuse Bazel action and repository artifacts.

Every Bazel invocation writes a JSON profile under:

```text
C:\opt\bazel-profiles
```

and the wrapper writes a PowerShell transcript there unless `-NoTranscript` is supplied.

## Verify build

```powershell
.\windows_build_fast.ps1 -Mode Verify
```

This first runs the two fast Gemma4 contracts, then builds the historical full Windows verification target set:

```text
//src:ovms
//src:ovms_test
//third_party:espeak_ng
//third_party:espeak_ng_data
```

Unlike the historical batch script, the wrapper invokes Bazel directly, so its native process exit code is the authority rather than a `bazel | tee` pipeline result.

For Verify/Package the wrapper temporarily stamps `src/version.hpp`, builds with that content, then restores the exact original tracked file in `finally`. Dev mode does not stamp it at all. A successful build therefore must not dirty `src/version.hpp`.

## Package

```powershell
.\windows_build_fast.ps1 -Mode Package
```

Package mode runs the Verify build and then calls the existing package creator. The current package creator still rebuilds the embedded Python staging environment; this is intentionally left as a separate optimization because package construction is outside the inner compile loop.

## CPU parallelism

By default the wrapper leaves Bazel's scheduler at its own default instead of forcing `%NUMBER_OF_PROCESSORS%`.

To benchmark an explicit cap:

```powershell
.\windows_build_fast.ps1 -Mode Dev -Jobs 4
.\windows_build_fast.ps1 -Mode Dev -Jobs 6
.\windows_build_fast.ps1 -Mode Dev -Jobs 8
```

Compare the generated Bazel profiles before making a machine-specific default permanent.

## Python-disabled build

```powershell
.\windows_build_fast.ps1 -Mode Dev -WithPython:$false
```

This selects `--config=win_mp_on_py_off` and uses a separate Bazel configuration key.

## MSVC discovery

The wrapper resolves the latest Visual Studio installation with the C++ x64/x86 tools via `vswhere.exe`, then reads the actual installed toolset from:

```text
VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt
```

It exports `BAZEL_VS`, `BAZEL_VC` and `BAZEL_VC_FULL_VERSION` for the current process. This avoids the historical hard-coded VC toolset version in `windows_build.bat`.

## Fast test targets

Generator:

```text
//src/test/llm/generation_config:gemma4_generation_contract_test
```

Parser:

```text
//src/test/llm/gemma4_fast:gemma4_parser_contract_test
```

The parser fast target intentionally duplicates the critical Parser v2 semantic corpus from the full OVMS suite. It is an inner-loop gate, not a replacement for the historical `//src:ovms_test` acceptance build.

## Clean-tree invariant

Recommended before and after every build:

```powershell
git status --short
git diff -- src/version.hpp
```

A Dev/Verify build using the new wrapper must not leave tracked build-generated modifications behind.
