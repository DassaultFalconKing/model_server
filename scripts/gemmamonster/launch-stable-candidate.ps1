[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CandidateRoot,
    [Parameter(Mandatory=$true)][string]$ModelPath,
    [string]$ModelName = 'gemma4-26-heretic',
    [int]$RestPort = 8000,
    [string[]]$OvmsArgs = @(),
    [int]$HealthcheckSeconds = 90,
    [switch]$NoHealthcheck
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Require-File([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing ${Label}: $Path" }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Test-PortFree([int]$Port) {
    try {
        $listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
        return @($listeners).Count -eq 0
    } catch {
        return $true
    }
}

function Test-HashManifest([string]$Root, [string]$ShaFile) {
    $bad = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content -LiteralPath $ShaFile -Encoding ASCII) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '^([0-9a-fA-F]{64})\s+(.+)$') { $bad.Add("malformed: $line"); continue }
        $expected = $Matches[1].ToLowerInvariant()
        $rel = $Matches[2].Trim()
        $path = Join-Path $Root $rel
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $bad.Add("missing: $rel"); continue }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) { $bad.Add("sha mismatch: $rel manifest=$expected actual=$actual") }
    }
    if ($bad.Count -gt 0) { throw "Candidate hash manifest failed:`n$($bad -join "`n")" }
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
$shaPath = Require-File (Join-Path $candidate 'SHA256SUMS.txt') 'candidate SHA256SUMS.txt'
Test-HashManifest $candidate $shaPath

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.candidate_kind -ne 'stable-2026.4-rc2-refit') {
    throw "Wrong candidate_kind '$($manifest.candidate_kind)'. This launcher accepts only stable-2026.4-rc2-refit packages."
}

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
try {
    $env:PATH = "$ovmsDir;$oldPath"
    Push-Location $ovmsDir
    try {
        $proc = Start-Process -FilePath $ovmsExe -ArgumentList $argList -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru -WindowStyle Hidden
    } finally {
        Pop-Location
    }
} finally {
    $env:PATH = $oldPath
}

[ordered]@{
    schema_version = 1
    launched_at_utc = [DateTime]::UtcNow.ToString('o')
    pid = $proc.Id
    candidate_root = $candidate
    source_sha = [string]$manifest.source_sha
    binary_path = $ovmsExe
    binary_sha256 = (Get-FileHash -LiteralPath $ovmsExe -Algorithm SHA256).Hash.ToLowerInvariant()
    model_path = $model
    model_name = $ModelName
    rest_port = $RestPort
    command = $ovmsExe + ' ' + ($argList -join ' ')
    path_policy = 'candidate ovms/ prepended for process launch; loaded module check follows'
    stdout_log = $stdoutLog
    stderr_log = $stderrLog
    healthcheck = if ($NoHealthcheck) { 'NOT_RUN' } else { $healthJson }
    loaded_modules = $modulesJson
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $launchJson -Encoding UTF8

if (-not $NoHealthcheck) {
    $ok = Invoke-ModelsHealthcheck -Port $RestPort -Seconds $HealthcheckSeconds -OutPath $healthJson
    if (-not $ok) { Write-Warning "Healthcheck failed or timed out. See $healthJson" }
}

try {
    $modules = Get-Process -Id $proc.Id -ErrorAction Stop | ForEach-Object {
        $_.Modules | Where-Object { $_.ModuleName -match 'openvino|genai|tokenizer|tbb' } |
            Select-Object ModuleName,FileName
    }
    $modules | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $modulesJson -Encoding UTF8
    foreach ($module in $modules) {
        $fileName = [string]$module.FileName
        if ($fileName -and -not $fileName.StartsWith($ovmsDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Loaded runtime module outside candidate package: $fileName"
        }
    }
} catch {
    if ($_.Exception.Message -like 'Loaded runtime module outside*') { throw }
    Write-Warning "Could not inspect loaded modules: $($_.Exception.Message)"
}

Write-Host 'GEMMAMONSTER STABLE CANDIDATE LAUNCHED'
Write-Host "  PID:           $($proc.Id)"
Write-Host "  SOURCE_SHA:    $($manifest.source_sha)"
Write-Host "  CANDIDATE:     $candidate"
Write-Host "  LAUNCH_JSON:   $launchJson"
Write-Host "  MODULES_JSON:  $modulesJson"
