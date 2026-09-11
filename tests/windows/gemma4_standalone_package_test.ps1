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

$manifest = Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
# optimum_bundled missing (old manifests) means bundled: early candidates always had it.
$optimumBundled = $true
$optimumFlag = $manifest.tooling.PSObject.Properties['optimum_bundled']
if ($null -ne $optimumFlag) { $optimumBundled = [bool]$optimumFlag.Value }

Push-Location $ovmsDir
# Packaged ovms.exe dies bare with 0xC0000005; it needs its setupvars env
# (same proven cause as the builder version capture).
$pkgPythonHome = [Environment]::GetEnvironmentVariable('PYTHONHOME', 'Process')
$pkgPath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
[Environment]::SetEnvironmentVariable('PYTHONHOME', (Join-Path $ovmsDir 'python'), 'Process')
[Environment]::SetEnvironmentVariable('PATH', "$ovmsDir;$ovmsDir\python;$ovmsDir\python\Scripts;$pkgPath", 'Process')
try {
    $version = & $ovmsExe --version 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Packaged ovms.exe --version failed.' }
    $versionText = ($version | Out-String)
    if ($versionText -match '2026\.5') { throw "2026.5 component reported by stable package:`n$versionText" }
    if ($versionText -notmatch '2026\.4') { throw "No 2026.4 component reported by stable package:`n$versionText" }

    & $ovmsExe --help | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Packaged ovms.exe --help failed.' }

    & (Join-Path $ovmsDir 'python\python.exe') --version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Bundled python.exe --version failed.' }
    if ($optimumBundled) {
        & (Join-Path $ovmsDir 'tools\optimum\optimum-cli.cmd') --help | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Bundled optimum-cli --help failed.' }
    } else {
        Write-Host 'Optimum tooling not bundled (lean flavor); skipping optimum-cli check.'
    }
} finally {
    if ($null -eq $pkgPythonHome) { Remove-Item 'Env:PYTHONHOME' -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable('PYTHONHOME', $pkgPythonHome, 'Process') }
    [Environment]::SetEnvironmentVariable('PATH', $pkgPath, 'Process')
    Pop-Location
}

Write-Host 'GEMMA4_STANDALONE_PACKAGE_TEST_PASS'
Write-Host "  source_sha:      $($result.source_sha)"
Write-Host "  runtime_profile: $($result.runtime_profile)"
Write-Host "  ovms_sha256:     $($result.ovms_sha256)"
Write-Host "  candidate_root:  $root"
