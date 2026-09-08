# GEMMAMONSTER-OVMS testing artifact manifest

- Source repository: `https://github.com/DassaultFalconKing/model_server.git`
- Source branch before artifact split: `docs/gemma4-local-acceptance-execution`
- Known-good source commit: `fea1a5f1c2640aa60fe6a840d3f62b38fb7b7767`
- Launcher commit: `024416b1`
- Binary: `ovms.exe`
- Binary SHA-256: `0683A62C602AE83EF70D13EF175663EE772843C7924B5C63D93287198CBB8E9B`
- Binary size: `22480384` bytes
- OVMS backend: `2026.4.0-22930-61afcb26271-releases/2026/4`
- OpenVINO GenAI backend: `2026.4.0.0-3401-5f7f1278107`
- Runtime pipeline: `VLM_CB`
- Runtime queue size: `0`
- REST endpoint used: `http://127.0.0.1:8888/v3`
- Model name: `gemma4`

The Bazel path `bazel-model_server-gemma4-fast` was deliberately not copied:
it is a workstation-local junction to `C:\b_tmp\bvmxypto\execroot\ovms`, not a
portable build artifact. The actual built executable is included instead.

`smoke_100_tool_calls.py` is preserved at the repository root as requested. It
was not the source of the strict result below because its environment lacked
the Python `requests` dependency and it targets the older `/v1` base path. The
verified 100-call result came from
`tools/gemmamonster-ovms/Test-GemmaMonsterOvms.ps1 -Count 100 -RequireToolCall`.
