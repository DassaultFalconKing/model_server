[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CandidateManifest,
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [string]$TargetBranch = 'integration/gemma4-parser-generator-refit-next',
    [switch]$DryRun,
    [switch]$AllowProtocolOnly,
    [switch]$WriteReport
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Require-File([string]$Path, [string]$Label) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing $Label: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-JsonFile([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Normalize-Status([object]$Manifest) {
    if ($Manifest.status) { return [string]$Manifest.status }
    return 'UNKNOWN'
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$manifestPath = Require-File $CandidateManifest 'candidate manifest'
$manifest = Get-JsonFile $manifestPath
$candidateDir = if ($manifest.candidate_dir) { [string]$manifest.candidate_dir } else { Split-Path -Parent $manifestPath }

if (-not $manifest.source_sha) { throw 'Manifest is missing source_sha.' }
if (-not $manifest.tree_sha) { throw 'Manifest is missing tree_sha.' }
if (-not $manifest.branch) { throw 'Manifest is missing branch.' }
if (-not $manifest.binary -or -not $manifest.binary.path -or -not $manifest.binary.sha256) {
    throw 'Manifest is missing binary.path or binary.sha256.'
}

$binaryPath = Require-File ([string]$manifest.binary.path) 'candidate binary'
$actualBinarySha = (Get-FileHash -LiteralPath $binaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
$expectedBinarySha = ([string]$manifest.binary.sha256).ToLowerInvariant()
if ($actualBinarySha -ne $expectedBinarySha) {
    throw "Binary SHA256 mismatch. manifest=$expectedBinarySha actual=$actualBinarySha"
}

$buildLog = Require-File ([string]$manifest.build_log) 'build log'
$status = Normalize-Status $manifest
$protocolOverall = if ($manifest.tests -and $manifest.tests.protocol_overall) { [string]$manifest.tests.protocol_overall } else { 'NOT_RUN' }
$protocolSummary = if ($manifest.tests -and $manifest.tests.protocol_summary) { [string]$manifest.tests.protocol_summary } else { $null }
$protocolLog = if ($manifest.tests -and $manifest.tests.protocol_log) { [string]$manifest.tests.protocol_log } else { $null }

if ($protocolOverall -ne 'PASS') {
    if (-not $DryRun) {
        throw "Protocol tests are not PASS for this candidate: $protocolOverall"
    }
}
if ($protocolSummary) { $protocolSummary = Require-File $protocolSummary 'protocol summary' }
if ($protocolLog) { $protocolLog = Require-File $protocolLog 'protocol log' }

if ($status -notin @('protocol_pass', 'live_pass', 'known_good')) {
    if (-not $DryRun) {
        throw "Candidate status '$status' is not promotable. Required: protocol_pass, live_pass, or known_good."
    }
}
if (-not $AllowProtocolOnly -and $status -eq 'protocol_pass' -and -not $DryRun) {
    throw 'Candidate has protocol_pass only. Pass -AllowProtocolOnly to promote source/test status without live acceptance.'
}

$reportName = ([DateTime]::UtcNow.ToString('yyyy-MM-dd-HHmmss') + '-' + ([string]$manifest.source_sha).Substring(0, 8) + '-candidate-acceptance.md')
$reportRel = Join-Path 'docs\gemmamonster\acceptance' $reportName
$reportPath = Join-Path $root $reportRel
$reportDir = Split-Path -Parent $reportPath
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

$report = @"
# Gemmamonster Candidate Acceptance Report

Generated UTC: $([DateTime]::UtcNow.ToString('o'))

## Candidate identity

| Field | Value |
| --- | --- |
| Source SHA | `$($manifest.source_sha)` |
| Tree SHA | `$($manifest.tree_sha)` |
| Branch | `$($manifest.branch)` |
| Candidate directory | `$candidateDir` |
| Binary SHA256 | `$actualBinarySha` |
| Status | `$status` |
| Target branch | `$TargetBranch` |

## Evidence

| Gate | Status | Evidence |
| --- | --- | --- |
| Build | PASS | `$buildLog` |
| Protocol | `$protocolOverall` | `$protocolSummary` |
| Launch/live | $($manifest.launch.status) | `$($manifest.launch.latest_launch_json)` |

## Promotion decision

Dry run: `$($DryRun.IsPresent)`

Promotion is permitted only when this report is backed by the manifest and logs above. This script does not move protected branches or tags automatically.

## Required handoff

```text
BRANCH: $($manifest.branch)
HEAD_SHA: $($manifest.source_sha)
BUILD: PASS, see $buildLog
TESTS: $protocolOverall, see $protocolSummary
ARTIFACTS: $candidateDir
PROMOTION_RECOMMENDATION: review and fast-forward/cherry-pick manually after evidence review
```
"@

if ($WriteReport -or $DryRun) {
    $report | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

Write-Host 'GEMMAMONSTER PROMOTION GATE'
Write-Host "  SOURCE_SHA:       $($manifest.source_sha)"
Write-Host "  BINARY_SHA256:    $actualBinarySha"
Write-Host "  STATUS:           $status"
Write-Host "  PROTOCOL:         $protocolOverall"
Write-Host "  TARGET_BRANCH:    $TargetBranch"
if ($WriteReport -or $DryRun) {
    Write-Host "  REPORT:           $reportPath"
}
if ($DryRun) {
    Write-Host '  RESULT:           DRY_RUN_ONLY'
} else {
    Write-Host '  RESULT:           PROMOTION_ALLOWED_BY_LOCAL_GATE'
    Write-Host '  NOTE:             branch movement is intentionally manual'
}
