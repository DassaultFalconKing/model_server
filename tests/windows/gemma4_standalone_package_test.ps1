[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CandidateRoot,
    [Parameter(Mandatory = $true)][string]$ExpectedGitSha,
    [ValidateSet('maintainer-rc2','known-good-rc1')][string]$ExpectedRuntimeProfile = 'maintainer-rc2'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $CandidateRoot).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$verifier = Join-Path $repoRoot 'scripts\gemmamonster\Test-StableCandidate.ps1'
if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) { throw "Candidate verifier missing: $verifier" }

$result = & $verifier -CandidateRoot $root -ExpectedSourceSha $ExpectedGitSha -ExpectedRuntimeProfile $ExpectedRuntimeProfile
if ($LASTEXITCODE -ne 0) { throw 'Stable candidate verifier failed.' }

$ovmsDir = Join-Path $root 'ovms'
$ovmsExe = Join-Path $ovmsDir 'ovms.exe'
$archive = Join-Path $root 'ovms.zip'
foreach ($required in @(
    $ovmsExe,
    (Join-Path $root 'manifest.json'),
    (Join-Path $root 'SHA256SUMS.txt'),
    (Join-Path $root 'provenance\source.json'),
    (Join-Path $root 'provenance\dependencies.json'),
    (Join-Path $root 'provenance\build.json'),
    (Join-Path $root 'provenance\package.json'),
    $archive
)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing candidate envelope entry: $required" }
}

Push-Location $ovmsDir
try {
    $version = & $ovmsExe --version 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Packaged ovms.exe --version failed.' }
    $versionText = ($version | Out-String)
    if ($versionText -match '2026\.5') { throw "2026.5 component reported by stable package:`n$versionText" }
    if ($versionText -notmatch '2026\.4') { throw "No 2026.4 component reported by stable package:`n$versionText" }

    & $ovmsExe --help | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Packaged ovms.exe --help failed.' }
} finally {
    Pop-Location
}

Write-Host 'GEMMA4_STANDALONE_PACKAGE_TEST_PASS'
Write-Host "  source_sha:      $($result.source_sha)"
Write-Host "  runtime_profile: $($result.runtime_profile)"
Write-Host "  ovms_sha256:     $($result.ovms_sha256)"
Write-Host "  candidate_root:  $root"
