[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [string]$ShortRoot = 'g54',
    [string]$ArtifactRoot = 'C:\gemmamonster-artifacts\candidates\2026.4-rc2',
    [string]$Label = 'latest-refit',
    [switch]$SkipDependencies,
    [switch]$ExpungeDependencies,
    [switch]$NoPython,
    [switch]$WithoutTests,
    [switch]$Integrity,
    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-GitValue([string]$Repo, [string[]]$Args) {
    $out = (& git -C $Repo @Args 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "git $($Args -join ' ') failed in $Repo" }
    return ($out | Out-String).Trim()
}

function Sanitize-Name([string]$Value) {
    $safe = $Value -replace '[^A-Za-z0-9_.-]', '-'
    $safe = $safe.Trim('-')
    if (-not $safe) { return 'candidate' }
    return $safe
}

function Require-File([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing ${Label}: $Path" }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Assert-StableVersions([string]$VersionsText) {
    if ($VersionsText -notmatch '2026\.4\.0\.0rc2') {
        throw 'versions.mk does not point at maintainer 2026.4 RC2 package line.'
    }
    if ($VersionsText -match '2026\.5\.0\.0|dev20260903|9b1d5c9494e838d42b5ed90d662c8ce84e5742f8|2e3b291a30e84fa067b042e35b8826d18d273882') {
        throw 'versions.mk contains 2026.5 runtime pins. This stable builder refuses mixed runtime lineage.'
    }
}

function Write-JsonFile([object]$Value, [string]$Path, [int]$Depth = 12) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$head = Get-GitValue $root @('rev-parse', 'HEAD')
$tree = Get-GitValue $root @('rev-parse', "$head^{tree}")
$branch = Get-GitValue $root @('rev-parse', '--abbrev-ref', 'HEAD')
$dirtyLines = @(& git -C $root status --porcelain)
$dirty = $dirtyLines.Count -gt 0
if ($dirty -and -not $AllowDirty) {
    throw 'Working tree is dirty. Commit/stash changes or pass -AllowDirty to record the dirty state in the manifest.'
}

$versionsPath = Require-File (Join-Path $root 'versions.mk') 'versions.mk'
$versionsText = Get-Content -LiteralPath $versionsPath -Raw -Encoding UTF8
Assert-StableVersions $versionsText

$depsBat = Require-File (Join-Path $root 'windows_install_build_dependencies.bat') 'dependency installer'
$buildBat = Require-File (Join-Path $root 'windows_build.bat') 'Windows builder'
$packageBat = Require-File (Join-Path $root 'windows_create_package.bat') 'Windows package builder'

$timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$safeLabel = Sanitize-Name $Label
$candidateName = "$($head.Substring(0, 8))-$safeLabel-$timestamp"
$candidateRoot = Join-Path $ArtifactRoot $candidateName
if (Test-Path -LiteralPath $candidateRoot) { throw "Candidate root already exists: $candidateRoot" }
New-Item -ItemType Directory -Path $candidateRoot -Force | Out-Null
foreach ($dir in @('logs','provenance','acceptance','dumps')) {
    New-Item -ItemType Directory -Path (Join-Path $candidateRoot $dir) -Force | Out-Null
}

$buildLog = Join-Path $candidateRoot 'logs\build.log'
$packageLog = Join-Path $candidateRoot 'logs\package.log'
$versionLog = Join-Path $candidateRoot 'provenance\ovms-version.txt'

Push-Location $root
try {
    if (-not $SkipDependencies) {
        $expunge = if ($ExpungeDependencies) { '1' } else { '0' }
        $integrityArg = if ($Integrity) { '1' } else { '0' }
        Write-Host "Installing pinned maintainer 2026.4 RC2 dependencies under C:\$ShortRoot (expunge=$expunge integrity=$integrityArg)"
        & $depsBat $ShortRoot $expunge $integrityArg 2>&1 | Tee-Object -FilePath (Join-Path $candidateRoot 'logs\dependencies.log')
        if ($LASTEXITCODE -ne 0) { throw "Dependency installation failed with exit code $LASTEXITCODE" }
    }

    $pythonArg = if ($NoPython) { '' } else { '--with_python' }
    $testsArg = if ($WithoutTests) { '' } else { '--with_tests' }
    Write-Host "Building OVMS stable refit HEAD=$head shortRoot=C:\$ShortRoot python=$(-not $NoPython) tests=$(-not $WithoutTests)"
    & $buildBat $ShortRoot $pythonArg $testsArg 2>&1 | Tee-Object -FilePath $buildLog
    if ($LASTEXITCODE -ne 0) { throw "Build failed with exit code $LASTEXITCODE. See $buildLog" }

    Write-Host "Creating isolated package under $candidateRoot"
    & $packageBat $ShortRoot $pythonArg $candidateRoot 2>&1 | Tee-Object -FilePath $packageLog
    if ($LASTEXITCODE -ne 0) { throw "Package creation failed with exit code $LASTEXITCODE. See $packageLog" }
} finally {
    Pop-Location
}

$ovmsDir = Join-Path $candidateRoot 'ovms'
$ovmsExe = Require-File (Join-Path $ovmsDir 'ovms.exe') 'packaged ovms.exe'

$versionOutput = & cmd.exe /d /c "cd /d `"$ovmsDir`" && ovms.exe --version" 2>&1
$versionExit = $LASTEXITCODE
$versionOutput | Set-Content -LiteralPath $versionLog -Encoding UTF8
if ($versionExit -ne 0) { throw "Packaged ovms.exe --version failed with exit code $versionExit. See $versionLog" }
$versionText = ($versionOutput | Out-String)
if ($versionText -match '2026\.5') {
    throw 'Packaged candidate reports a 2026.5 component. Refusing stable-2026.4 candidate.'
}
if ($versionText -notmatch '2026\.4') {
    throw 'Packaged candidate did not report any 2026.4 component. Check ovms-version.txt before accepting.'
}

$runtimeFiles = Get-ChildItem -LiteralPath $ovmsDir -Recurse -File | Sort-Object FullName
$shaLines = foreach ($file in $runtimeFiles) {
    $rel = [System.IO.Path]::GetRelativePath($candidateRoot, $file.FullName).Replace('\','/')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $rel"
}
$shaPath = Join-Path $candidateRoot 'SHA256SUMS.txt'
$shaLines | Set-Content -LiteralPath $shaPath -Encoding ASCII

$dlls = @('openvino.dll','openvino_genai.dll','openvino_tokenizers.dll','tbb12.dll')
$dllHash = [ordered]@{}
foreach ($dll in $dlls) {
    $path = Join-Path $ovmsDir $dll
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $dllHash[$dll] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$manifestPath = Join-Path $candidateRoot 'manifest.json'
$manifest = [ordered]@{
    schema_version = 1
    project = 'GEMMAMONSTER'
    candidate_kind = 'stable-2026.4-rc2-refit'
    repository = 'DassaultFalconKing/model_server'
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    candidate_name = $candidateName
    candidate_root = $candidateRoot
    branch = $branch
    source_sha = $head
    tree_sha = $tree
    repo_dirty = $dirty
    short_root = "C:\$ShortRoot"
    runtime_policy = 'self-contained ovms/ package; do not accept bare bazel-bin/src/ovms.exe for runtime acceptance'
    versions_mk_sha256 = (Get-FileHash -LiteralPath $versionsPath -Algorithm SHA256).Hash.ToLowerInvariant()
    versions_mk_expected_line = 'maintainer 2026.4 RC2, never 2026.5'
    package = [ordered]@{
        ovms_dir = $ovmsDir
        ovms_exe = $ovmsExe
        ovms_sha256 = (Get-FileHash -LiteralPath $ovmsExe -Algorithm SHA256).Hash.ToLowerInvariant()
        runtime_file_count = $runtimeFiles.Count
        sha256sums = $shaPath
        dll_sha256 = $dllHash
    }
    logs = [ordered]@{
        build = $buildLog
        package = $packageLog
        version = $versionLog
    }
    acceptance = [ordered]@{
        status = 'NOT_RUN'
        required_before_known_good = @(
            'parser contracts',
            'generation contracts',
            'prompt-state contracts',
            'streaming same-tool repeated calls',
            'real OpenCode workload on Arc 140V'
        )
    }
}
Write-JsonFile $manifest $manifestPath 12

Write-Host ''
Write-Host 'GEMMAMONSTER STABLE 2026.4 RC2 CANDIDATE BUILT'
Write-Host "  SOURCE_SHA:       $head"
Write-Host "  BRANCH:           $branch"
Write-Host "  CANDIDATE_ROOT:   $candidateRoot"
Write-Host "  OVMS_SHA256:      $($manifest.package.ovms_sha256)"
Write-Host "  MANIFEST:         $manifestPath"
Write-Host "  VERSION_EVIDENCE: $versionLog"
Write-Host '  STATUS:           BUILT_NOT_ACCEPTED'
