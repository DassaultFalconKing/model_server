$ErrorActionPreference = "Stop"
$env:PYTHONHOME = "C:\opt\Python312"
$env:PYTHONPATH = $null
Set-Location "C:\git\model_server-gemma4-google-template-session-state"
& "C:\opt\Python312\python.exe" `
  ".\ab-evidence\reliability_grounded_harness_v2.py" `
  --base-url "http://127.0.0.1:18000" `
  --model "gemma4-26-heretic" `
  --binary ".\bazel-bin\src\ovms.exe" `
  --git-sha "2cb5a9a0e8d22732de2d1c89f52795c2de612a57" `
  --production-sha "7d00c5fe63c5f81e6c06972a974cd57fd7180326" `
  --out-dir "C:\git\Session-state-data\runs\20260907T044637Z-2cb5a9a0\reliability-v2-live" `
  --timeout 180 `
  --campaign all `
  --no-resume
exit $LASTEXITCODE
