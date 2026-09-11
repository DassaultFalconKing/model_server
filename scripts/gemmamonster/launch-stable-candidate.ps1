[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CandidateRoot,
    [Parameter(Mandatory=$true)][string]$ModelPath,
    [string]$ModelName = 'gemma4-26-heretic',
    [int]$RestPort = 8000,
    [string[]]$OvmsArgs = @(),
    [int]$HealthcheckSeconds = 90,
    [switch]$NoHealthcheck,
    [switch]$AllowUnverifiedModules
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Require-File([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing ${Label}: $Path" }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-PortFree([int]$Port) {
    try {
        $listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
        return @($listeners).Count -eq 0
    } catch {
        return $true
    }
}

function Invoke-ModelsHealthcheck([int]$Port, [int]$Seconds, [string]$OutPath) {
    $uri = "http://127.0.0.1:$Port/v1/models"
    $deadline = (Get-Date).AddSeconds($Seconds)
    $lastError = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 2
            [ordered]@{status='PASS';uri=$uri;status_code=[int]$resp.StatusCode;body=$resp.Content;checked_at_utc=[DateTime]::UtcNow.ToString('o')} |
                ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutPath -Encoding UTF8
            return $true
        } catch {
            $lastError = $_.Exception.Message
            Start-Sleep -Seconds 2
        }
    }
    [ordered]@{status='FAIL';uri=$uri;error=$lastError;checked_at_utc=[DateTime]::UtcNow.ToString('o')} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutPath -Encoding UTF8
    return $false
}

$candidate = (Resolve-Path -LiteralPath $CandidateRoot).Path
$manifestPath = Require-File (Join-Path $candidate 'manifest.json') 'candidate manifest'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$verifier = Require-File (Join-Path $PSScriptRoot 'Test-StableCandidate.ps1') 'candidate verifier'
& $verifier -CandidateRoot $candidate -ExpectedSourceSha ([string]$manifest.source_sha) -ExpectedRuntimeProfile ([string]$manifest.runtime_profile) | Out-Null

$ovmsDir = Join-Path $candidate 'ovms'
$ovmsExe = Require-File (Join-Path $ovmsDir 'ovms.exe') 'packaged ovms.exe'
$model = (Resolve-Path -LiteralPath $ModelPath).Path
if (-not (Test-Path -LiteralPath $model)) { throw "Model path does not exist: $ModelPath" }

if (-not (Test-PortFree $RestPort)) {
    $owners = Get-NetTCPConnection -LocalPort $RestPort -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
    throw "REST port $RestPort is already occupied by PID(s): $($owners -join ', '). Refusing to test an unknown server."
}

$runDir = Join-Path (Join-Path $candidate 'acceptance') ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$stdoutLog = Join-Path $runDir 'ovms.stdout.log'
$stderrLog = Join-Path $runDir 'ovms.stderr.log'
$launchJson = Join-Path $runDir 'launch.json'
$healthJson = Join-Path $runDir 'healthcheck.json'
$modulesJson = Join-Path $runDir 'loaded-modules.json'

$defaultArgs = @(
    '--rest_port', [string]$RestPort,
    '--model_path', $model,
    '--model_name', $ModelName,
    '--task', 'text_generation',
    '--tool_parser', 'gemma4',
    '--reasoning_parser', 'gemma4'
)
$argList = if (@($OvmsArgs).Count -gt 0) { $OvmsArgs } else { $defaultArgs }

$oldPath = $env:PATH
$oldPythonHome = $env:PYTHONHOME
$oldOvmsDir = $env:OVMS_DIR
try {
    # Spawned ovms dies bare with 0xC0000005 (same proven setupvars-env cause
    # as builder/package checks): it needs OVMS_DIR/PYTHONHOME, not just PATH.
    $env:OVMS_DIR = $ovmsDir
    $env:PYTHONHOME = Join-Path $ovmsDir 'python'
    $env:PATH = "$ovmsDir;$oldPath"
    Push-Location $ovmsDir
    try {
        $proc = Start-Process -FilePath $ovmsExe -ArgumentList $argList -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru -WindowStyle Hidden
    } finally {
        Pop-Location
    }
} finally {
    $env:PATH = $oldPath
    if ($null -eq $oldPythonHome) { Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue } else { $env:PYTHONHOME = $oldPythonHome }
    if ($null -eq $oldOvmsDir) { Remove-Item Env:OVMS_DIR -ErrorAction SilentlyContinue } else { $env:OVMS_DIR = $oldOvmsDir }
}

[ordered]@{
    schema_version = 2
    launched_at_utc = [DateTime]::UtcNow.ToString('o')
    pid = $proc.Id
    candidate_root = $candidate
    source_sha = [string]$manifest.source_sha
    runtime_profile = [string]$manifest.runtime_profile
    binary_path = $ovmsExe
    binary_sha256 = Get-Hash $ovmsExe
    model_path = $model
    model_name = $ModelName
    rest_port = $RestPort
    command = $ovmsExe + ' ' + ($argList -join ' ')
    path_policy = 'candidate ovms/ prepended; loaded OpenVINO/GenAI/Tokenizers/TBB modules must resolve inside package'
    stdout_log = $stdoutLog
    stderr_log = $stderrLog
    healthcheck = if ($NoHealthcheck) { 'NOT_RUN' } else { $healthJson }
    loaded_modules = $modulesJson
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $launchJson -Encoding UTF8

if (-not $NoHealthcheck) {
    $ok = Invoke-ModelsHealthcheck -Port $RestPort -Seconds $HealthcheckSeconds -OutPath $healthJson
    if (-not $ok) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw "Candidate failed healthcheck. Process stopped. Evidence: $healthJson"
    }
}

try {
    $process = Get-Process -Id $proc.Id -ErrorAction Stop
    $modules = @($process.Modules | Where-Object { $_.ModuleName -match 'openvino|genai|tokenizer|tbb' })
    if ($modules.Count -lt 4) {
        throw "Loaded module inspection returned only $($modules.Count) relevant module(s); expected at least OpenVINO, GenAI, Tokenizers and TBB."
    }

    $records = foreach ($module in $modules) {
        $fileName = [string]$module.FileName
        if ([string]::IsNullOrWhiteSpace($fileName)) { throw "Loaded module has no file path: $($module.ModuleName)" }
        $resolved = (Resolve-Path -LiteralPath $fileName).Path
        if (-not $resolved.StartsWith($ovmsDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Loaded runtime module outside candidate package: $resolved"
        }
        $hash = Get-Hash $resolved
        $expectedProperty = $manifest.package.dll_sha256.PSObject.Properties[[string]$module.ModuleName]
        if ($null -ne $expectedProperty) {
            $expected = ([string]$expectedProperty.Value).ToLowerInvariant()
            if ($hash -ne $expected) { throw "Loaded runtime module hash mismatch: $($module.ModuleName) expected=$expected actual=$hash path=$resolved" }
        }
        [ordered]@{ module = [string]$module.ModuleName; path = $resolved; sha256 = $hash; inside_candidate = $true }
    }
    [ordered]@{status='PASS';pid=$proc.Id;checked_at_utc=[DateTime]::UtcNow.ToString('o');modules=@($records)} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $modulesJson -Encoding UTF8
} catch {
    [ordered]@{status='FAIL';pid=$proc.Id;checked_at_utc=[DateTime]::UtcNow.ToString('o');error=$_.Exception.Message} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $modulesJson -Encoding UTF8
    if (-not $AllowUnverifiedModules) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw "Runtime module provenance could not be proven; process stopped. $($_.Exception.Message)"
    }
    Write-Warning "UNSAFE OVERRIDE: runtime module provenance not proven. $($_.Exception.Message)"
}

Write-Host 'GEMMAMONSTER STABLE CANDIDATE LAUNCHED'
Write-Host "  PID:              $($proc.Id)"
Write-Host "  SOURCE_SHA:       $($manifest.source_sha)"
Write-Host "  RUNTIME_PROFILE:  $($manifest.runtime_profile)"
Write-Host "  CANDIDATE:        $candidate"
Write-Host "  LAUNCH_JSON:      $launchJson"
Write-Host "  MODULES_JSON:     $modulesJson"
Write-Host '  STATUS:            RUNTIME_PROVENANCE_VERIFIED_NOT_ACCEPTED'
