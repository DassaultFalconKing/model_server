# GEMMAMONSTER Windows acceptance environment gate

Date: 2026-09-07
Status: LEADING ACCEPTANCE-INFRA CONTRACT

## Purpose

Before any source candidate can earn acceptance evidence on Windows, the local environment must be reproducible enough that a failed test means something about the code rather than about a hidden Python/Bash/MSVC/DLL trap.

This gate is intentionally separate from Gemma parser/generator semantics.

## Required preflight

Record and verify:

```text
REPO
BRANCH
HEAD
GIT_STATUS

BAZEL_EXE
BAZEL_VERSION
BAZEL_OUTPUT_USER_ROOT
BAZEL_REPOSITORY_CACHE
BAZEL_DISK_CACHE
BAZEL_SERVER_STATE

BAZEL_SH
MSYS_BASH

BAZEL_VS
BAZEL_VC
BAZEL_VC_FULL_VERSION
CL_EXE

PYTHONHOME_INITIAL
PYTHONHOME_EFFECTIVE
PYTHON_BIN_PATH
PYTHON_EXE
PYTHON_VERSION

OPENVINO_DIR
OPENVINO_VERSION
OPENCV_DIR
OPENCV_VERSION

GEMMA4_TOKENIZER_PATH
```

## Known Windows hazards

### Bazel executable

Do not assume `bazel` is on PATH. The environment investigation must resolve the actual executable, currently expected to be near:

```text
C:\opt\bazel.exe
```

and record its version.

### WSL bash vs MSYS bash

Windows `where bash` may resolve:

```text
C:\Windows\System32\bash.exe
```

which is a WSL launcher, not the MSYS bash Bazel expects for this build flow.

The intended candidate is:

```text
C:\opt\msys64\usr\bin\bash.exe
```

`BAZEL_SH` must be process-locally explicit when ambiguity exists.

### Python environment

A global `PYTHONHOME`, including a deployment/runtime Python directory, may poison Bazel repository configuration.

Known historical example:

```text
PYTHONHOME=C:\llm\ovms\python
```

The acceptance environment must distinguish:

- initial user/system environment;
- process-local environment required for Bazel;
- the Python executable actually used by `python_configure(name = "local_config_python")`.

Do not permanently mutate global environment variables to make a single test pass.

### `windows_build_fast.ps1` Python detection

A directory existence check is not sufficient evidence of a valid Python installation.

The script must ultimately be hardened so any configured Python root is accepted only when the expected executable exists and runs.

Until that fix is separately reviewed, the environment report must explicitly verify the actual `python.exe` path.

### MSVC

Record the exact Visual Studio/Build Tools root, VC directory, toolset version and `cl.exe` path.

An environment variable that merely points at an existing directory is not proof that Bazel can compile with it.

### DLL sandbox behavior

A Bazel test exiting with Windows status:

```text
-1073741515
STATUS_DLL_NOT_FOUND
```

is `BLOCKED`, not a test assertion failure.

The missing dependency and PATH/runfiles difference between manual binary execution and Bazel sandbox execution must be identified before the test result can be interpreted.

## Tokenizer fixture policy

Gemma4 parser unit tests may require an OpenVINO tokenizer artifact but do not automatically require the full 26B model.

The environment investigation must determine the minimal actual files required by:

```cpp
ov::genai::Tokenizer(...)
```

and use a process-local:

```text
GEMMA4_TOKENIZER_PATH
```

when a tokenizer-only fixture is sufficient.

Do not commit a large model artifact into the repository to solve a unit-test fixture problem.

## Focused test order

Do not start with the entire repository test suite.

Preferred order:

```text
1. //src/test/llm/generation_config:gemma4_generation_contract_test
2. //src/test/llm/generation_config:openai_parallel_tool_calls_contract_test
3. //src/test/llm/gemma4_fast:gemma4_parser_contract_test
4. //src/test:kfs_rest_test
5. //src/test/llm:max_model_length_test
```

Only after focused targets are executable should a broader test/build campaign be attempted.

## Result semantics

For each test:

```text
PASS    = binary ran and assertions passed
FAIL    = binary ran and assertions failed
BLOCKED = toolchain/fixture/DLL/build/analysis prevented the test contract from running
NOT_RUN = not attempted
```

Manual invocation of a test binary may provide diagnostic evidence, but it does not silently convert a Bazel `STATUS_DLL_NOT_FOUND` result into Bazel PASS.

## Build gate

Before live Arc acceptance, the exact clean integration candidate must produce a Windows OVMS build from the documented environment.

At minimum record:

```text
source SHA
build command
build configuration
exit code
binary path
binary SHA256
OVMS reported version
```

## Unit vs live requirements

Keep these separate.

### Unit/compile lane may require

- Bazel/MSYS/MSVC/Python;
- OpenVINO/OpenCV development environment;
- tokenizer fixture;
- dependent runtime DLLs for tests.

### Live lane additionally requires

- patched `ovms.exe` built from exact candidate;
- target Intel Arc host/device;
- Gemma4 model;
- pinned canonical chat template;
- deployment profile;
- HTTP/runtime harness;
- raw request/response/server-log capture.

The absence of a 26B model is not a universal excuse for failing to run parser/generator unit contracts.

## Promotion relationship

This environment gate is a prerequisite for the C++/Windows portions of [`ACCEPTANCE-MATRIX-V1.md`](ACCEPTANCE-MATRIX-V1.md). It does not replace the live matrix.
