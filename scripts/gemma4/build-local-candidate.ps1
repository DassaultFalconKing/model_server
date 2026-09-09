[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [string]$ShortRoot = 'g5',
    [string]$Label = '2026.5-candidate',
    [switch]$SkipDependencies,
    [switch]$ExpungeDependencies,
    [switch]$NoPython,
    [switch]$WithoutTests,
    [switch]$Integrity
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$work = Join-Path $root ("tmp\gemmamonster-acceptance\" + $Label)
New-Item -ItemType Directory -Path $work -Force | Out-Null

$auditScript = Join-Path $root 'scripts\gemma4\audit-forward-port.ps1'
$auditOut = Join-Path $work 'static-audit.json'
& $auditScript -RepoRoot $root -OutputPath $auditOut
if ($LASTEXITCODE -ne 0) { throw "Static forward-port audit failed. See $auditOut" }

$head = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve source HEAD' }

$depsBat = Join-Path $root 'windows_install_build_dependencies.bat'
$buildBat = Join-Path $root 'windows_build.bat'
if (-not (Test-Path -LiteralPath $depsBat)) { throw "Missing $depsBat" }
if (-not (Test-Path -LiteralPath $buildBat)) { throw "Missing $buildBat" }

if (-not $SkipDependencies) {
    $expunge = if ($ExpungeDependencies) { '1' } else { '0' }
    Write-Host "Installing/updating pinned 2026.5 dependencies under C:\$ShortRoot (expunge=$expunge)"
    Push-Location $root
    try {
        & $depsBat $ShortRoot $expunge '0'
        if ($LASTEXITCODE -ne 0) { throw "windows_install_build_dependencies.bat failed with exit code $LASTEXITCODE" }
    } finally { Pop-Location }
}

$pythonArg = if ($NoPython) { '' } else { '--with_python' }
$testsArg = if ($WithoutTests) { '' } else { '--with_tests' }
$integrityArg = if ($Integrity) { '--integrity' } else { '' }
Write-Host "Building OVMS HEAD=$head python=$(-not $NoPython) tests=$(-not $WithoutTests) integrity=$($Integrity.IsPresent)"
Push-Location $root
try {
    & $buildBat $ShortRoot $pythonArg $testsArg $integrityArg
    if ($LASTEXITCODE -ne 0) { throw "windows_build.bat failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }

$candidates = @(
    (Join-Path $root 'bazel-bin\src\ovms.exe'),
    (Join-Path $root 'bazel-out\x64_windows-opt\bin\src\ovms.exe')
)
$ovms = $null
foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $ovms = (Resolve-Path -LiteralPath $candidate).Path; break }
}
if (-not $ovms) {
    $found = Get-ChildItem -LiteralPath $root -Filter ovms.exe -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'bazel-(bin|out)' } |
        Select-Object -First 1
    if ($found) { $ovms = $found.FullName }
}
if (-not $ovms) { throw 'Build returned success but ovms.exe could not be located under bazel-bin/bazel-out.' }

$openVinoDir = "C:\$ShortRoot\openvino"
$provenancePath = Join-Path $work 'runtime-provenance.json'
$provenanceScript = Join-Path $root 'scripts\gemma4\collect-runtime-provenance.ps1'
& $provenanceScript -OvmsPath $ovms -OutputPath $provenancePath -OpenVinoDir $openVinoDir -RepoPath $root

$versions = Get-Content -LiteralPath (Join-Path $root 'versions.mk') -Raw -Encoding UTF8
$record = [ordered]@{
    schema_version = 1
    label = $Label
    built_at_utc = [DateTime]::UtcNow.ToString('o')
    repo_root = $root
    git_head = $head
    short_root = $ShortRoot
    openvino_dir = $openVinoDir
    ovms_exe = $ovms
    ovms_sha256 = (Get-FileHash -LiteralPath $ovms -Algorithm SHA256).Hash.ToLowerInvariant()
    with_python = -not $NoPython
    with_tests = -not $WithoutTests
    integrity = $Integrity.IsPresent
    versions_mk_sha256 = (Get-FileHash -LiteralPath (Join-Path $root 'versions.mk') -Algorithm SHA256).Hash.ToLowerInvariant()
    versions_mk = $versions
    static_audit = $auditOut
    runtime_provenance = $provenancePath
    known_pending = @('src/llm/apis/openai_responses.cpp parallel_tool_calls response serialization one-line local patch')
}
$candidatePath = Join-Path $work 'candidate.json'
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $candidatePath -Encoding UTF8

Write-Host ''
Write-Host 'LOCAL BUILD CANDIDATE PREPARED'
Write-Host "  HEAD:       $head"
Write-Host "  ovms.exe:   $ovms"
Write-Host "  SHA256:     $($record.ovms_sha256)"
Write-Host "  candidate:  $candidatePath"
Write-Host '  status:     COMPILED, NOT YET RUNTIME-ACCEPTED'
