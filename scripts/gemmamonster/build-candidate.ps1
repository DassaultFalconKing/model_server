[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [string]$Label = 'gemmamonster-candidate',
    [string]$ArtifactRoot = '',
    [string]$ShortRoot = 'g5',
    [switch]$SkipDependencies,
    [switch]$ExpungeDependencies,
    [switch]$NoPython,
    [switch]$WithoutTests,
    [switch]$Integrity,
    [switch]$RunProtocol,
    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Sanitize-Name([string]$Value) {
    $safe = $Value -replace '[^A-Za-z0-9_.-]', '-'
    $safe = $safe.Trim('-')
    if (-not $safe) { return 'candidate' }
    return $safe
}

function Get-GitValue([string]$Repo, [string[]]$GitArgs) {
    $out = (& git -C $Repo @GitArgs 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed" }
    return ($out | Out-String).Trim()
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$head = Get-GitValue $root @('rev-parse', 'HEAD')
$tree = Get-GitValue $root @('rev-parse', "$head^{tree}")
$branch = Get-GitValue $root @('rev-parse', '--abbrev-ref', 'HEAD')
$statusLines = & git -C $root status --porcelain
$dirty = @($statusLines).Count -gt 0
if ($dirty -and -not $AllowDirty) {
    throw 'Working tree is dirty. Commit/stash changes or pass -AllowDirty to record a dirty candidate.'
}

if (-not $ArtifactRoot) {
    $ArtifactRoot = $env:GEMMAMONSTER_ARTIFACT_ROOT
}
if (-not $ArtifactRoot) {
    $ArtifactRoot = 'C:\gemmamonster-artifacts\candidates'
}

$timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$safeLabel = Sanitize-Name $Label
$candidateName = $head.Substring(0, 8) + '-' + $safeLabel + '-' + $timestamp
$candidateDir = Join-Path $ArtifactRoot $candidateName
New-Item -ItemType Directory -Path $candidateDir -Force | Out-Null

$builder = Join-Path $root 'scripts\gemma4\build-local-candidate.ps1'
if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
    throw "Missing Gemma4 build helper: $builder"
}

$buildLog = Join-Path $candidateDir 'build.log'
$buildArgs = @('-RepoRoot', $root, '-ShortRoot', $ShortRoot, '-Label', $Label)
if ($SkipDependencies) { $buildArgs += '-SkipDependencies' }
if ($ExpungeDependencies) { $buildArgs += '-ExpungeDependencies' }
if ($NoPython) { $buildArgs += '-NoPython' }
if ($WithoutTests) { $buildArgs += '-WithoutTests' }
if ($Integrity) { $buildArgs += '-Integrity' }
# Array splatting passes values positionally, which cannot bind to the
# builder's [CmdletBinding()] named parameters. Splat by name instead.
$buildSplat = @{ RepoRoot = $root; ShortRoot = $ShortRoot; Label = $Label }
if ($SkipDependencies) { $buildSplat['SkipDependencies'] = $true }
if ($ExpungeDependencies) { $buildSplat['ExpungeDependencies'] = $true }
if ($NoPython) { $buildSplat['NoPython'] = $true }
if ($WithoutTests) { $buildSplat['WithoutTests'] = $true }
if ($Integrity) { $buildSplat['Integrity'] = $true }

Write-Host "BUILD_CANDIDATE starting"
Write-Host "  SOURCE_SHA: $head"
Write-Host "  BRANCH:     $branch"
Write-Host "  DIR:        $candidateDir"

& $builder @buildSplat 2>&1 | Tee-Object -FilePath $buildLog
$buildExit = $LASTEXITCODE
if ($buildExit -ne 0) {
    throw "build-local-candidate.ps1 failed with exit code $buildExit. See $buildLog"
}

$legacyDir = Join-Path $root ("tmp\gemmamonster-acceptance\" + $Label)
$legacyCandidate = Join-Path $legacyDir 'candidate.json'
if (-not (Test-Path -LiteralPath $legacyCandidate -PathType Leaf)) {
    throw "Build completed but legacy candidate metadata is missing: $legacyCandidate"
}
$legacy = Get-Content -LiteralPath $legacyCandidate -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceOvms = [string]$legacy.ovms_exe
if (-not (Test-Path -LiteralPath $sourceOvms -PathType Leaf)) {
    throw "Build completed but ovms.exe is missing: $sourceOvms"
}

$copiedOvms = Join-Path $candidateDir 'ovms.exe'
Copy-Item -LiteralPath $sourceOvms -Destination $copiedOvms -Force
Copy-Item -LiteralPath $legacyCandidate -Destination (Join-Path $candidateDir 'legacy-candidate.json') -Force
foreach ($maybe in @($legacy.static_audit, $legacy.runtime_provenance)) {
    if ($maybe -and (Test-Path -LiteralPath $maybe -PathType Leaf)) {
        Copy-Item -LiteralPath $maybe -Destination (Join-Path $candidateDir (Split-Path -Leaf $maybe)) -Force
    }
}

$binarySha = (Get-FileHash -LiteralPath $copiedOvms -Algorithm SHA256).Hash.ToLowerInvariant()
$protocolOverall = 'NOT_RUN'
$protocolSummaryPath = $null
$protocolLog = $null
$protocolExit = $null

if ($RunProtocol) {
    $runner = Join-Path $root 'scripts\gemma4\test-protocol-hardening.ps1'
    if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
        throw "Missing protocol runner: $runner"
    }
    $protocolLog = Join-Path $candidateDir 'protocol-runner.log'
    & $runner -RepoRoot $root -Label $Label 2>&1 | Tee-Object -FilePath $protocolLog
    $protocolExit = $LASTEXITCODE
    $latestSummary = Get-ChildItem -LiteralPath $legacyDir -Filter 'summary.json' -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($latestSummary) {
        $protocolSummaryPath = Join-Path $candidateDir 'protocol-summary.json'
        Copy-Item -LiteralPath $latestSummary.FullName -Destination $protocolSummaryPath -Force
        $summary = Get-Content -LiteralPath $protocolSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $protocolOverall = [string]$summary.overall
    } else {
        $protocolOverall = if ($protocolExit -eq 0) { 'PASS_NO_SUMMARY' } else { 'FAIL_NO_SUMMARY' }
    }
    if ($protocolExit -ne 0) {
        Write-Warning "Protocol runner failed with exit code $protocolExit. Candidate will remain built_not_accepted."
    }
}

$status = 'built_not_accepted'
if ($RunProtocol -and $protocolExit -eq 0 -and $protocolOverall -eq 'PASS') {
    $status = 'protocol_pass'
}

$versionsPath = Join-Path $root 'versions.mk'
$manifest = [ordered]@{
    schema_version = 1
    project = 'Gemmamonster'
    repository = 'DassaultFalconKing/model_server'
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    label = $Label
    candidate_name = $candidateName
    candidate_dir = $candidateDir
    branch = $branch
    source_sha = $head
    tree_sha = $tree
    repo_dirty = $dirty
    build_profile = [ordered]@{
        short_root = $ShortRoot
        with_python = -not $NoPython
        with_tests = -not $WithoutTests
        integrity = $Integrity.IsPresent
        skip_dependencies = $SkipDependencies.IsPresent
        expunge_dependencies = $ExpungeDependencies.IsPresent
    }
    build_command = 'scripts/gemma4/build-local-candidate.ps1 ' + ($buildArgs -join ' ')
    build_log = $buildLog
    binary = [ordered]@{
        path = $copiedOvms
        source_path = $sourceOvms
        sha256 = $binarySha
        size_bytes = (Get-Item -LiteralPath $copiedOvms).Length
    }
    legacy_candidate = (Join-Path $candidateDir 'legacy-candidate.json')
    versions_mk_sha256 = if (Test-Path -LiteralPath $versionsPath -PathType Leaf) { (Get-FileHash -LiteralPath $versionsPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
    tests = [ordered]@{
        protocol_requested = $RunProtocol.IsPresent
        protocol_exit_code = $protocolExit
        protocol_overall = $protocolOverall
        protocol_log = $protocolLog
        protocol_summary = $protocolSummaryPath
    }
    launch = [ordered]@{
        status = 'NOT_RUN'
        latest_launch_json = $null
    }
    status = $status
}

$manifestPath = Join-Path $candidateDir 'manifest.json'
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$shaFile = Join-Path $candidateDir 'sha256sums.txt'
@(
    "$binarySha  ovms.exe",
    "$((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant())  manifest.json"
) | Set-Content -LiteralPath $shaFile -Encoding ASCII

Write-Host ''
Write-Host 'GEMMAMONSTER CANDIDATE'
Write-Host "  SOURCE_SHA:    $head"
Write-Host "  TREE_SHA:      $tree"
Write-Host "  BRANCH:        $branch"
Write-Host "  BINARY_SHA256: $binarySha"
Write-Host "  MANIFEST:      $manifestPath"
Write-Host "  STATUS:        $status"

if ($status -ne 'protocol_pass') {
    Write-Host '  CLAIM:         binary built, not accepted'
}
