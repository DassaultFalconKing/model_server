# GEMMAMONSTER-OVMS Windows launcher

These scripts run the locally built custom OVMS from this repository with the
known-good Gemma 4 `VLM_CB` profile. The source HEAD must contain commit
`fea1a5f1c2640aa60fe6a840d3f62b38fb7b7767`.

Validate paths and generate the runtime graph without starting OVMS:

```powershell
.\tools\gemmamonster-ovms\Start-GemmaMonsterOvms.ps1 -ValidateOnly
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
