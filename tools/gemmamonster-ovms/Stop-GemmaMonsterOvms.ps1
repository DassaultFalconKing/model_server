param(
    [string]$RuntimeRoot = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "runtime\gemmamonster-ovms")
)

$ErrorActionPreference = "Stop"
$RuntimeRoot = [System.IO.Path]::GetFullPath($RuntimeRoot)
$PidPath = Join-Path $RuntimeRoot "ovms.pid"

if (-not (Test-Path -LiteralPath $PidPath -PathType Leaf)) {
    Write-Host "No GEMMAMONSTER-OVMS PID file found under $RuntimeRoot"
    return
}

$PidValue = (Get-Content -LiteralPath $PidPath -Raw).Trim()
$ProcessId = 0
if (-not [int]::TryParse($PidValue, [ref]$ProcessId)) {
    throw "Invalid PID file content in $PidPath"
}

$Process = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
if ($Process) {
    $ExpectedConfig = (Join-Path $RuntimeRoot "config.json")
    if ($Process.Name -ne "ovms.exe" -or $Process.CommandLine -notlike "*$ExpectedConfig*") {
        throw "PID $ProcessId does not identify the GEMMAMONSTER-OVMS instance for $RuntimeRoot"
    }
    Stop-Process -Id $ProcessId -Force
    Write-Host "Stopped GEMMAMONSTER-OVMS PID $ProcessId"
}
else {
    Write-Host "GEMMAMONSTER-OVMS PID $ProcessId is no longer running"
}

Remove-Item -LiteralPath $PidPath -Force
