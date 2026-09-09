[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CandidateDir,
    [Parameter(Mandatory=$true)][string]$ModelPath,
    [string]$ModelName = 'gemmamonster-gemma4',
    [int]$RestPort = 8000,
    [string[]]$OvmsArgs = @(),
    [int]$HealthcheckSeconds = 60,
    [switch]$NoHealthcheck
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-PortFree([int]$Port) {
    try {
        $listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
        return @($listeners).Count -eq 0
    } catch {
        return $true
    }
}

function Invoke-JsonHealthcheck([string]$Uri, [int]$Seconds, [string]$OutPath) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    $lastError = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 2
            $record = [ordered]@{
                uri = $Uri
                status = 'PASS'
                status_code = [int]$resp.StatusCode
                checked_at_utc = [DateTime]::UtcNow.ToString('o')
                body = $resp.Content
            }
            $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutPath -Encoding UTF8
            return $true
        } catch {
            $lastError = $_.Exception.Message
            Start-Sleep -Seconds 2
        }
    }
    $record = [ordered]@{
        uri = $Uri
        status = 'FAIL'
        checked_at_utc = [DateTime]::UtcNow.ToString('o')
        error = $lastError
    }
    $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutPath -Encoding UTF8
    return $false
}

$candidateRoot = (Resolve-Path -LiteralPath $CandidateDir).Path
$manifestPath = Join-Path $candidateRoot 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Missing candidate manifest: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

$ovms = Join-Path $candidateRoot 'ovms.exe'
if (-not (Test-Path -LiteralPath $ovms -PathType Leaf)) {
    throw "Missing candidate binary: $ovms"
}
$actualSha = (Get-FileHash -LiteralPath $ovms -Algorithm SHA256).Hash.ToLowerInvariant()
$expectedSha = [string]$manifest.binary.sha256
if ($actualSha -ne $expectedSha) {
    throw "Binary SHA256 mismatch. manifest=$expectedSha actual=$actualSha"
}

$model = (Resolve-Path -LiteralPath $ModelPath).Path
if (-not (Test-Path -LiteralPath $model)) {
    throw "Model path does not exist: $ModelPath"
}

if (-not (Test-PortFree $RestPort)) {
    $owners = Get-NetTCPConnection -LocalPort $RestPort -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
    throw "REST port $RestPort is already occupied by PID(s): $($owners -join ', '). Refusing to test an unknown server."
}

$runtimeDir = Join-Path (Join-Path $candidateRoot 'runtime') ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
$stdoutLog = Join-Path $runtimeDir 'ovms.stdout.log'
$stderrLog = Join-Path $runtimeDir 'ovms.stderr.log'
$launchJson = Join-Path $runtimeDir 'launch.json'
$healthJson = Join-Path $runtimeDir 'healthcheck.json'

$defaultArgs = @(
    '--rest_port', [string]$RestPort,
    '--model_path', $model,
    '--model_name', $ModelName,
    '--task', 'text_generation',
    '--tool_parser', 'gemma4',
    '--reasoning_parser', 'gemma4'
)
$argList = if (@($OvmsArgs).Count -gt 0) { $OvmsArgs } else { $defaultArgs }

$proc = Start-Process -FilePath $ovms -ArgumentList $argList -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru -WindowStyle Hidden

$launch = [ordered]@{
    schema_version = 1
    launched_at_utc = [DateTime]::UtcNow.ToString('o')
    pid = $proc.Id
    candidate_dir = $candidateRoot
    manifest = $manifestPath
    source_sha = [string]$manifest.source_sha
    branch = [string]$manifest.branch
    binary_path = $ovms
    binary_sha256 = $actualSha
    model_path = $model
    model_name = $ModelName
    rest_port = $RestPort
    command = $ovms + ' ' + ($argList -join ' ')
    stdout_log = $stdoutLog
    stderr_log = $stderrLog
    healthcheck = if ($NoHealthcheck) { 'NOT_RUN' } else { $healthJson }
}
$launch | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $launchJson -Encoding UTF8

if (-not $NoHealthcheck) {
    $ok = Invoke-JsonHealthcheck -Uri ("http://127.0.0.1:$RestPort/v1/models") -Seconds $HealthcheckSeconds -OutPath $healthJson
    if (-not $ok) {
        Write-Warning "Healthcheck did not pass within $HealthcheckSeconds seconds. See $healthJson"
    }
}

Write-Host 'GEMMAMONSTER CANDIDATE LAUNCHED'
Write-Host "  PID:           $($proc.Id)"
Write-Host "  SOURCE_SHA:    $($manifest.source_sha)"
Write-Host "  BINARY_SHA256: $actualSha"
Write-Host "  LAUNCH_JSON:   $launchJson"
Write-Host "  STDOUT:        $stdoutLog"
Write-Host "  STDERR:        $stderrLog"
