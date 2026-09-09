[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OvmsExe,
    [Parameter(Mandatory = $true)][string]$ModelName,
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [string]$BaseUrl = 'http://127.0.0.1:8000',
    [string]$CommitSha = '',
    [string]$Label = '2026.5-candidate',
    [string]$PythonExe = '',
    [ValidateSet('None', 'Smoke', 'Full')][string]$Reliability = 'Smoke',
    [int]$TimeoutSeconds = 180,
    [string]$TemplateProvenancePath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$ovms = (Resolve-Path -LiteralPath $OvmsExe).Path
if ([string]::IsNullOrWhiteSpace($CommitSha)) {
    $CommitSha = (& git -C $root rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve acceptance commit SHA' }
}
if ($CommitSha -notmatch '^[0-9a-f]{40}$') { throw "CommitSha must be a lowercase 40-hex git SHA: $CommitSha" }
$resolved = (& git -C $root rev-parse "$CommitSha^{commit}").Trim()
if ($LASTEXITCODE -ne 0 -or $resolved -ne $CommitSha) { throw "CommitSha cannot be resolved exactly in ${root}: $CommitSha" }
$head = (& git -C $root rev-parse HEAD).Trim()
if ($head -ne $CommitSha) { throw "Acceptance requires worktree HEAD to equal CommitSha. HEAD=$head requested=$CommitSha" }

if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    if (Test-Path -LiteralPath 'C:\opt\Python312\python.exe') { $PythonExe = 'C:\opt\Python312\python.exe' } else { $PythonExe = 'python' }
}

# Do not let an unrelated embedded Python installation poison the harness.
# This script runs in a child pwsh process, so normalizing its process-level
# environment does not modify the user's persistent environment.
Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $PythonExe -PathType Leaf) {
    $candidatePythonHome = Split-Path -Parent (Resolve-Path -LiteralPath $PythonExe).Path
    if (Test-Path -LiteralPath (Join-Path $candidatePythonHome 'Lib\encodings') -PathType Container) {
        $env:PYTHONHOME = $candidatePythonHome
    }
}

try {
    $ready = Invoke-WebRequest -Uri ($BaseUrl.TrimEnd('/') + '/v2/health/ready') -TimeoutSec 10 -UseBasicParsing
    if ($ready.StatusCode -ne 200) { throw "readiness returned $($ready.StatusCode)" }
} catch {
    throw "OVMS is not ready at $BaseUrl. Launch it before acceptance. $($_.Exception.Message)"
}

$outRoot = Join-Path $root ("tmp\gemmamonster-acceptance\" + $Label + '-' + $CommitSha.Substring(0, 8))
New-Item -ItemType Directory -Path $outRoot -Force | Out-Null
$auditOut = Join-Path $outRoot 'static-audit.json'
& (Join-Path $root 'scripts\gemma4\audit-forward-port.ps1') -RepoRoot $root -OutputPath $auditOut
if ($LASTEXITCODE -ne 0) { throw 'Static forward-port audit failed before live acceptance.' }

$provenanceArgs = @{
    OvmsPath = $ovms
    OutputPath = (Join-Path $outRoot 'runtime-provenance.json')
    RepoPath = $root
}
if (-not [string]::IsNullOrWhiteSpace($TemplateProvenancePath)) {
    $provenanceArgs.TemplateProvenancePath = $TemplateProvenancePath
}
& (Join-Path $root 'scripts\gemma4\collect-runtime-provenance.ps1') @provenanceArgs

$chain = Join-Path $root 'ab-evidence\live_chain_harness.py'
$catalog = Join-Path $root 'ab-evidence\complex-tool-catalog.json'
$chainResults = New-Object System.Collections.Generic.List[object]
foreach ($mode in @('named', 'required', 'auto')) {
    $modeOut = Join-Path $outRoot ("chain-" + $mode)
    Write-Host "Running chained tool acceptance: $mode"
    & $PythonExe $chain `
        --base-url $BaseUrl `
        --model $ModelName `
        --repo-root $root `
        --commit-sha $CommitSha `
        --catalog $catalog `
        --out-dir $modeOut `
        --second-tool-choice $mode `
        --timeout $TimeoutSeconds
    $rc = $LASTEXITCODE
    $chainResults.Add([ordered]@{ mode = $mode; exit_code = $rc; out_dir = $modeOut })
    if ($rc -ne 0) { throw "Chained acceptance failed in mode=$mode. Evidence: $modeOut" }
}

$reliabilityOut = $null
if ($Reliability -ne 'None') {
    $reliabilityScript = Join-Path $root 'ab-evidence\reliability_grounded_harness_v2.py'
    $autoOut = Join-Path $outRoot 'chain-auto'
    $frozenRequest = Join-Path $autoOut 'request2-input.json'
    $frozenToolResult = Join-Path $autoOut 'tool1-result.json'
    if (-not (Test-Path -LiteralPath $frozenRequest) -or -not (Test-Path -LiteralPath $frozenToolResult)) {
        throw 'Auto chain did not produce request2/tool1 evidence required by reliability harness.'
    }
    $reliabilityOut = Join-Path $outRoot 'reliability'
    $args = @(
        $reliabilityScript,
        '--base-url', $BaseUrl,
        '--model', $ModelName,
        '--binary', $ovms,
        '--git-sha', $CommitSha,
        '--production-sha', 'c48366fee1f10cdf6b5fe3c181522ed0c58fc9fd',
        '--parser-name', 'gemma4',
        '--chat-template-mode', 'JINJA',
        '--catalog', $catalog,
        '--frozen-request2', $frozenRequest,
        '--frozen-tool-result', $frozenToolResult,
        '--grounded-fixtures', (Join-Path $root 'ab-evidence\grounded-facts-fixtures.json'),
        '--grounded-catalog', (Join-Path $root 'ab-evidence\grounded-facts-catalog.json'),
        '--out-dir', $reliabilityOut,
        '--timeout', [string]$TimeoutSeconds
    )
    if ($Reliability -eq 'Smoke') {
        $args += @(
            '--n-named', '2', '--n-required', '2',
            '--n-auto-a1', '2', '--n-auto-a2', '1', '--n-auto-a3', '1', '--n-auto-a4', '1', '--n-auto-a5', '1',
            '--n-think-off', '1', '--n-think-on', '1', '--n-think-sample-off', '0', '--n-think-sample-on', '0',
            '--n-b-repeats', '1'
        )
    }
    Write-Host "Running reliability campaign: $Reliability"
    & $PythonExe @args
    if ($LASTEXITCODE -ne 0) { throw "Reliability campaign failed. Evidence: $reliabilityOut" }
    $trialsPath = Join-Path $reliabilityOut 'trials.jsonl'
    if (-not (Test-Path -LiteralPath $trialsPath -PathType Leaf)) {
        throw "Reliability campaign produced no trials.jsonl. Evidence: $reliabilityOut"
    }
    $failedTrials = @(
        Get-Content -LiteralPath $trialsPath -Encoding UTF8 |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_ | ConvertFrom-Json } |
            Where-Object { $_.primary_outcome -ne 'PASS' }
    )
    if ($failedTrials.Count -gt 0) {
        $failedIds = @($failedTrials | ForEach-Object { $_.trial_id }) -join ', '
        throw "Reliability campaign NOT_ACCEPTED: $($failedTrials.Count) failed trial(s): $failedIds. Evidence: $reliabilityOut"
    }
}

$record = [ordered]@{
    schema_version = 1
    completed_at_utc = [DateTime]::UtcNow.ToString('o')
    verdict = 'PASS'
    label = $Label
    git_head = $CommitSha
    known_good_2026_4 = 'c48366fee1f10cdf6b5fe3c181522ed0c58fc9fd'
    ovms_exe = $ovms
    ovms_sha256 = (Get-FileHash -LiteralPath $ovms -Algorithm SHA256).Hash.ToLowerInvariant()
    model = $ModelName
    base_url = $BaseUrl
    # Windows PowerShell/PowerShell 7 can throw "Argument types do not match"
    # when @() materializes a generic List whose entries are ordered dictionaries.
    # Enumerate explicitly so the evidence summary always receives a plain array.
    chained_tool_modes = @($chainResults | ForEach-Object { $_ })
    reliability = $Reliability
    reliability_out = $reliabilityOut
    static_audit = $auditOut
    known_pending = @('Responses endpoint parallel_tool_calls serialization one-line local patch may still be uncommitted; chat-completions generation acceptance is authoritative for this run.')
}
$summaryPath = Join-Path $outRoot 'candidate-acceptance.json'
$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host ''
Write-Host 'GEMMAMONSTER LOCAL CANDIDATE ACCEPTANCE PASS'
Write-Host "  HEAD:      $CommitSha"
Write-Host "  evidence:  $outRoot"
Write-Host "  summary:   $summaryPath"
