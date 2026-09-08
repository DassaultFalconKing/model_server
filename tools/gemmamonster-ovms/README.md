# GEMMAMONSTER-OVMS Windows launcher

These scripts run the locally built custom OVMS from this repository with
diagnostic Gemma 4 profiles. The source HEAD must contain commit
`fea1a5f1c2640aa60fe6a840d3f62b38fb7b7767`.

Profiles are intentionally small experiments:

- `A`: legacy `VLM`, no prefix caching, one sequence.
- `B`: `VLM_CB`, no prefix caching, DQ group size 0, one sequence.
- `C`: `VLM_CB`, prefix caching enabled; otherwise identical to B.

Start with profile B for the correctness-isolation run. Use A to separate a
general VLM/long-context problem from CB, and C only to test the incremental
effect of prefix reuse. Do not change several performance knobs at once.

Validate paths and generate the runtime graph without starting OVMS:

```powershell
.\tools\gemmamonster-ovms\Start-GemmaMonsterOvms.ps1 -ValidateOnly
```

Select a diagnostic profile explicitly:

```powershell
.\tools\gemmamonster-ovms\Start-GemmaMonsterOvms.ps1 -Profile B
```

Start it in the background on REST port 8888 and gRPC port 9000:

```powershell
.\tools\gemmamonster-ovms\Start-GemmaMonsterOvms.ps1
```

Run one strict OpenAI-compatible named-tool request:

```powershell
.\tools\gemmamonster-ovms\Test-GemmaMonsterOvms.ps1 -RequireToolCall
```

Run the 100-call acceptance probe:

```powershell
.\tools\gemmamonster-ovms\Test-GemmaMonsterOvms.ps1 -Count 100 -RequireToolCall
```

Run the long-context acceptance matrix (300–450 token free-text generation,
exact tool arguments, streaming, and a tool-result second turn):

```powershell
.\tools\gemmamonster-ovms\Test-GemmaMonsterAcceptance.ps1
```

The matrix uses persistent history targets near 2k, 4k, 8k, 12k, and 16k
prompt tokens. Every raw unary JSON and streaming SSE response is saved under
`runtime/gemmamonster-acceptance/<run-id>` for review. A slow 8k–16k request is
not itself a failure; a closed connection, dead process, malformed response,
wrong tool argument, or morphemic/low-diversity text is.

The same endpoints can be called with `curl.exe`:

```powershell
curl.exe -sS http://127.0.0.1:8888/v3/models
curl.exe -sS -H "Content-Type: application/json" `
  -d '{"model":"gemma4","messages":[{"role":"user","content":"Reply with OK"}],"max_tokens":16}' `
  http://127.0.0.1:8888/v3/chat/completions
```

Stop only the instance recorded by this launcher's PID file:

```powershell
.\tools\gemmamonster-ovms\Stop-GemmaMonsterOvms.ps1
```

The generated configuration, PID, and logs are stored under
`runtime/gemmamonster-ovms`. That directory is a local runtime artifact and
must not be committed.
