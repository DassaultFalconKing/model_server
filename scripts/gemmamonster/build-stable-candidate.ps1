[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [ValidateSet('maintainer-rc2','known-good-rc1')][string]$RuntimeProfile = 'maintainer-rc2',
    [string]$ShortRoot = '',
    [string]$ArtifactRoot = 'C:\gemmamonster-artifacts\candidates\2026.4',
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

. (Join-Path $PSScriptRoot 'stable-runtime-profiles.ps1')

function Get-GitValue([string]$Repo, [string[]]$GitArgs) {
    $out = (& git.exe -C $Repo @GitArgs 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed in $Repo" }
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

function Write-JsonFile([object]$Value, [string]$Path, [int]$Depth = 14) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Assert-SourceVersionsAuthority([string]$VersionsText) {
    $authority = Get-GemmamonsterStableRuntimeProfile -Name 'maintainer-rc2'
    foreach ($pair in @(
        @('OV_SOURCE_BRANCH', $authority.OV_SOURCE_BRANCH),
        @('OV_TOKENIZERS_BRANCH', $authority.OV_TOKENIZERS_BRANCH),
        @('OV_GENAI_BRANCH', $authority.OV_GENAI_BRANCH),
        @('GENAI_PACKAGE_URL_WINDOWS', $authority.GENAI_PACKAGE_URL_WINDOWS)
    )) {
        $name = $pair[0]
        $value = $pair[1]
        $escaped = [regex]::Escape($value)
        if ($VersionsText -notmatch "(?m)^$([regex]::Escape($name))\s*\?=\s*$escaped\s*$") {
            throw "versions.mk source authority mismatch for ${name}. Expected exact maintainer-rc2 value: $value"
        }
    }
    if ($VersionsText -match '2026\.5') { throw 'versions.mk contains a 2026.5 marker. Refusing stable branch build.' }
}

function Get-Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-SameFile([string]$ExpectedPath, [string]$ActualPath, [string]$Label) {
    $expected = Get-Hash $ExpectedPath
    $actual = Get-Hash $ActualPath
    if ($expected -ne $actual) {
        throw "Packaged runtime provenance mismatch for ${Label}: source=$ExpectedPath ($expected) packaged=$ActualPath ($actual)"
    }
    return [ordered]@{ source_path = $ExpectedPath; source_sha256 = $expected; packaged_path = $ActualPath; packaged_sha256 = $actual }
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$profile = Get-GemmamonsterStableRuntimeProfile -Name $RuntimeProfile
if ([string]::IsNullOrWhiteSpace($ShortRoot)) { $ShortRoot = [string]$profile.default_short_root }
if ($ShortRoot -notmatch '^[A-Za-z0-9_.-]+$') { throw "ShortRoot must be a simple C:\ directory name, got: $ShortRoot" }

$head = Get-GitValue $root @('rev-parse', 'HEAD')
$tree = Get-GitValue $root @('rev-parse', "$head^{tree}")
$branch = Get-GitValue $root @('rev-parse', '--abbrev-ref', 'HEAD')
$dirtyLines = @(& git -C $root status --porcelain)
$dirty = $dirtyLines.Count -gt 0
if ($dirty -and -not $AllowDirty) {
    throw 'Working tree is dirty before build. Commit/stash changes or pass -AllowDirty; dirty candidates cannot become known-good.'
}

$versionsPath = Require-File (Join-Path $root 'versions.mk') 'versions.mk'
$versionsText = Get-Content -LiteralPath $versionsPath -Raw -Encoding UTF8
Assert-SourceVersionsAuthority $versionsText
$versionsHash = Get-Hash $versionsPath

$depsBat = Require-File (Join-Path $root 'windows_install_build_dependencies.bat') 'dependency installer'
$buildBat = Require-File (Join-Path $root 'windows_build.bat') 'Windows builder'
$packageBat = Require-File (Join-Path $root 'windows_create_package.bat') 'Windows package builder'
$verifier = Require-File (Join-Path $root 'scripts\gemmamonster\Test-StableCandidate.ps1') 'candidate verifier'

$mutableTracked = [ordered]@{}
foreach ($relative in @('WORKSPACE','src\version.hpp')) {
    $path = Require-File (Join-Path $root $relative) $relative
    $mutableTracked[$relative] = [ordered]@{
        path = $path
        bytes = [System.IO.File]::ReadAllBytes($path)
        sha256 = Get-Hash $path
    }
}
$trackedFilesRestored = $false

$timestamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$safeLabel = Sanitize-Name $Label
$candidateName = "$($head.Substring(0, 8))-$RuntimeProfile-$safeLabel-$timestamp"
$candidateRoot = Join-Path $ArtifactRoot $candidateName
if (Test-Path -LiteralPath $candidateRoot) { throw "Candidate root already exists: $candidateRoot" }
New-Item -ItemType Directory -Path $candidateRoot -Force | Out-Null
foreach ($dir in @('logs','provenance','acceptance','dumps')) {
    New-Item -ItemType Directory -Path (Join-Path $candidateRoot $dir) -Force | Out-Null
}

$buildLog = Join-Path $candidateRoot 'logs\build.log'
$packageLog = Join-Path $candidateRoot 'logs\package.log'
$dependencyLog = Join-Path $candidateRoot 'logs\dependencies.log'
$versionLog = Join-Path $candidateRoot 'provenance\ovms-version.txt'

$envNames = @('OV_SOURCE_BRANCH','OV_TOKENIZERS_BRANCH','OV_GENAI_BRANCH','GENAI_PACKAGE_URL_WINDOWS','GENAI_PACKAGE_URL','OV_USE_BINARY')
$savedEnv = @{}
foreach ($name in $envNames) { $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }

$buildSucceeded = $false
try {
    $env:OV_SOURCE_BRANCH = [string]$profile.OV_SOURCE_BRANCH
    $env:OV_TOKENIZERS_BRANCH = [string]$profile.OV_TOKENIZERS_BRANCH
    $env:OV_GENAI_BRANCH = [string]$profile.OV_GENAI_BRANCH
    $env:GENAI_PACKAGE_URL_WINDOWS = [string]$profile.GENAI_PACKAGE_URL_WINDOWS
    $env:GENAI_PACKAGE_URL = [string]$profile.GENAI_PACKAGE_URL_WINDOWS
    $env:OV_USE_BINARY = '1'

        Push-Location $root
    try {
        # Transient WORKSPACE pin rewrite (fail-closed).
        # Bazel new_local_repository pins for windows_openvino/windows_genai are
        # static (C:\opt\openvino\runtime = rc1 tree). Without this rewrite the
        # build links GenAI/Tokenizers from C:\opt regardless of $ShortRoot:
        # proven by candidate af2f7049 (rc2 core + rc1 GenAI 5f7f127, packaged
        # DLLs == C:\opt hashes). Restored byte-exact by the finally block
        # below (WORKSPACE is in $mutableTracked).
        $workspacePath = Join-Path $root 'WORKSPACE'
        $pinFrom = 'C:\\opt\\openvino\\runtime'
        $pinTo = "C:\\$ShortRoot\\openvino\\runtime"
        if ($pinTo -ne $pinFrom) {
            $workspaceText = [System.IO.File]::ReadAllText($workspacePath)
            $pinHits = ([regex]::Matches($workspaceText, [regex]::Escape($pinFrom))).Count
            if ($pinHits -ne 2) { throw "WORKSPACE pin rewrite refused: expected 2 '$pinFrom' pins, found $pinHits." }
            [System.IO.File]::WriteAllText($workspacePath, $workspaceText.Replace($pinFrom, $pinTo))
            Write-Host "WORKSPACE pins transiently rewritten to $pinTo (2 hits; restored after build)"
        }

        if (-not $SkipDependencies) {
            $expunge = if ($ExpungeDependencies) { '1' } else { '0' }
            $integrityArg = if ($Integrity) { '1' } else { '0' }
            Write-Host "Installing exact runtime profile '$RuntimeProfile' under C:\$ShortRoot"
            & $depsBat $ShortRoot $expunge $integrityArg 2>&1 | Tee-Object -FilePath $dependencyLog
            if ($LASTEXITCODE -ne 0) { throw "Dependency installation failed with exit code $LASTEXITCODE" }
        }

        $openvinoLink = "C:\$ShortRoot\openvino"
        if (-not (Test-Path -LiteralPath $openvinoLink -PathType Container)) { throw "Pinned OpenVINO/GenAI runtime root missing: $openvinoLink" }
        $linkItem = Get-Item -LiteralPath $openvinoLink -Force
        $linkTarget = [string]($linkItem.Target -join ';')
        if ($linkTarget -notlike "*$($profile.package_marker)*") {
            throw "Dependency root does not resolve to expected package marker '$($profile.package_marker)': $linkTarget"
        }

        $pythonArg = if ($NoPython) { '' } else { '--with_python' }
        $testsArg = if ($WithoutTests) { '' } else { '--with_tests' }
        Write-Host "Building stable refit HEAD=$head profile=$RuntimeProfile root=C:\$ShortRoot"
        & $buildBat $ShortRoot $pythonArg $testsArg 2>&1 | Tee-Object -FilePath $buildLog
        if ($LASTEXITCODE -ne 0) { throw "Build failed with exit code $LASTEXITCODE. See $buildLog" }

        Write-Host "Creating isolated package under $candidateRoot"
        & $packageBat $ShortRoot $pythonArg $candidateRoot 2>&1 | Tee-Object -FilePath $packageLog
        if ($LASTEXITCODE -ne 0) { throw "Package creation failed with exit code $LASTEXITCODE. See $packageLog" }
        $buildSucceeded = $true
    } finally {
        Pop-Location
    }
} finally {
    foreach ($entry in $mutableTracked.GetEnumerator()) {
        [System.IO.File]::WriteAllBytes([string]$entry.Value.path, [byte[]]$entry.Value.bytes)
    }
    $trackedFilesRestored = $true
    foreach ($entry in $mutableTracked.GetEnumerator()) {
        if ((Get-Hash ([string]$entry.Value.path)) -ne [string]$entry.Value.sha256) { $trackedFilesRestored = $false }
    }
    foreach ($name in $envNames) {
        $old = $savedEnv[$name]
        if ($null -eq $old) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, [string]$old, 'Process') }
    }
}

if (-not $trackedFilesRestored) { throw 'Build-mutated tracked files were not restored byte-for-byte.' }
if (-not $dirty) {
    # Bazel recreates its `bazel-<workspace>` execroot convenience link (untracked,
    # not covered by .gitignore which only lists bazel-bin/out/testlogs). Tolerate
    # exactly top-level untracked bazel-* links; anything else still fails closed.
    $postStatus = @(& git -C $root status --porcelain | Where-Object { $_ -notmatch '^\?\? bazel-[^/]*/$' })
    if ($postStatus.Count -gt 0) {
        throw "Build left unexpected worktree mutations after restoration:`n$($postStatus -join "`n")"
    }
}
if (-not $buildSucceeded) { throw 'Build/package did not complete successfully.' }

$ovmsDir = Join-Path $candidateRoot 'ovms'
$ovmsExe = Require-File (Join-Path $ovmsDir 'ovms.exe') 'packaged ovms.exe'

# ovms.exe --version crashes bare (0xC0000005) without its runtime env: it needs
# PYTHONHOME + PATH exactly as the packaged setupvars provides. Proven: same
# binary fails bare, passes with env (candidate 21044f8d GenAI 7ea2546852a).
$versionPythonHome = [Environment]::GetEnvironmentVariable('PYTHONHOME', 'Process')
$versionPath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
[Environment]::SetEnvironmentVariable('PYTHONHOME', (Join-Path $ovmsDir 'python'), 'Process')
[Environment]::SetEnvironmentVariable('PATH', "$ovmsDir;$ovmsDir\python;$ovmsDir\python\Scripts;$versionPath", 'Process')
try {
    $versionOutput = & cmd.exe /d /c "cd /d `"$ovmsDir`" && ovms.exe --version" 2>&1
    $versionExit = $LASTEXITCODE
} finally {
    if ($null -eq $versionPythonHome) { Remove-Item 'Env:PYTHONHOME' -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable('PYTHONHOME', $versionPythonHome, 'Process') }
    [Environment]::SetEnvironmentVariable('PATH', $versionPath, 'Process')
}
$versionOutput | Set-Content -LiteralPath $versionLog -Encoding UTF8
if ($versionExit -ne 0) { throw "Packaged ovms.exe --version failed with exit code $versionExit. See $versionLog" }
$versionText = ($versionOutput | Out-String)
if ($versionText -match '2026\.5') { throw 'Packaged candidate reports a 2026.5 component. Refusing stable-2026.4 candidate.' }
if ($versionText -notmatch '2026\.4') { throw 'Packaged candidate did not report a 2026.4 component.' }

$runtimeFiles = @(Get-ChildItem -LiteralPath $ovmsDir -Recurse -File | Sort-Object FullName)
$shaLines = foreach ($file in $runtimeFiles) {
    $rel = [System.IO.Path]::GetRelativePath($candidateRoot, $file.FullName).Replace('\','/')
    "$(Get-Hash $file.FullName)  $rel"
}
$shaPath = Join-Path $candidateRoot 'SHA256SUMS.txt'
$shaLines | Set-Content -LiteralPath $shaPath -Encoding ASCII

$sourcePaths = [ordered]@{
    'openvino.dll' = "C:\$ShortRoot\openvino\runtime\bin\intel64\Release\openvino.dll"
    'tbb12.dll' = "C:\$ShortRoot\openvino\runtime\3rdparty\tbb\bin\tbb12.dll"
    'openvino_genai.dll' = (Join-Path $root 'bazel-out\x64_windows-opt\bin\src\openvino_genai.dll')
    'openvino_tokenizers.dll' = (Join-Path $root 'bazel-out\x64_windows-opt\bin\src\openvino_tokenizers.dll')
}
$runtimeProvenance = [ordered]@{}
foreach ($name in $sourcePaths.Keys) {
    $sourcePath = Require-File $sourcePaths[$name] "source $name"
    $packagedPath = Require-File (Join-Path $ovmsDir $name) "packaged $name"
    $runtimeProvenance[$name] = Assert-SameFile $sourcePath $packagedPath $name
}

$dllHashes = [ordered]@{}
foreach ($name in @('openvino.dll','openvino_genai.dll','openvino_tokenizers.dll','tbb12.dll')) {
    $dllHashes[$name] = Get-Hash (Join-Path $ovmsDir $name)
}

$dependencyPins = [ordered]@{
    OV_SOURCE_BRANCH = [string]$profile.OV_SOURCE_BRANCH
    OV_TOKENIZERS_BRANCH = [string]$profile.OV_TOKENIZERS_BRANCH
    OV_GENAI_BRANCH = [string]$profile.OV_GENAI_BRANCH
    GENAI_PACKAGE_URL_WINDOWS = [string]$profile.GENAI_PACKAGE_URL_WINDOWS
}

$manifestPath = Join-Path $candidateRoot 'manifest.json'
$manifest = [ordered]@{
    schema_version = 2
    project = 'GEMMAMONSTER'
    candidate_kind = 'stable-2026.4-refit'
    runtime_profile = $RuntimeProfile
    repository = 'DassaultFalconKing/model_server'
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    candidate_name = $candidateName
    candidate_root = $candidateRoot
    branch = $branch
    source_sha = $head
    tree_sha = $tree
    repo_dirty = $dirty
    short_root = "C:\$ShortRoot"
    dependency_pins = $dependencyPins
    tooling = [ordered]@{
        python = [string]$profile.PYTHON_VERSION
        optimum = [string]$profile.OPTIMUM_VERSION
        optimum_intel = [string]$profile.OPTIMUM_INTEL_VERSION
        openvino = [string]$profile.OPTIMUM_OPENVINO_VERSION
        openvino_tokenizers = [string]$profile.OPTIMUM_OPENVINO_TOKENIZERS_VERSION
        isolation = 'ovms/tools/optimum/site-packages; excluded from OVMS runtime PATH'
    }
    source_authority = [ordered]@{
        versions_mk_sha256 = $versionsHash
        versions_mk_policy = 'branch stays exact latest-maintainer 2026.4 RC2; known-good RC1 is selected only by process environment overrides'
        restored_tracked_files = @($mutableTracked.Keys)
        restored_byte_exact = $trackedFilesRestored
    }
    runtime_policy = 'self-contained ovms/ package; acceptance must prove loaded modules are inside this package'
    package = [ordered]@{
        ovms_dir = $ovmsDir
        ovms_exe = $ovmsExe
        ovms_sha256 = Get-Hash $ovmsExe
        runtime_file_count = $runtimeFiles.Count
        sha256sums = $shaPath
        dll_sha256 = $dllHashes
        runtime_source_equivalence = $runtimeProvenance
        archive = (Join-Path $candidateRoot 'ovms.zip')
    }
    logs = [ordered]@{
        dependencies = $dependencyLog
        build = $buildLog
        package = $packageLog
        version = $versionLog
    }
    acceptance = [ordered]@{
        status = 'NOT_RUN'
        required_before_known_good = @(
            'source contract tests',
            'package contract test',
            'loaded module provenance',
            'repeated same-tool non-stream',
            'repeated same-tool stream',
            'multi-turn session continuity',
            'real OpenCode workload on Arc 140V',
            'RC1 versus RC2 A/B if stability differs'
        )
    }
}
Write-JsonFile $manifest $manifestPath 16

Write-JsonFile ([ordered]@{ source_sha=$head; tree_sha=$tree; branch=$branch; repo_dirty=$dirty; versions_mk_sha256=$versionsHash; restored_tracked_files=@($mutableTracked.Keys); restored_byte_exact=$trackedFilesRestored }) (Join-Path $candidateRoot 'provenance\source.json')
Write-JsonFile ([ordered]@{ runtime_profile=$RuntimeProfile; pins=$dependencyPins; short_root="C:\$ShortRoot"; package_marker=$profile.package_marker }) (Join-Path $candidateRoot 'provenance\dependencies.json')
Write-JsonFile ([ordered]@{ build_log=$buildLog; with_python=(-not $NoPython); with_tests=(-not $WithoutTests); restored_tracked_files=@($mutableTracked.Keys); restored_byte_exact=$trackedFilesRestored }) (Join-Path $candidateRoot 'provenance\build.json')
Write-JsonFile ([ordered]@{ ovms_sha256=$manifest.package.ovms_sha256; dlls=$runtimeProvenance; sha256sums=$shaPath; archive=$manifest.package.archive }) (Join-Path $candidateRoot 'provenance\package.json')

$verifyArgs = @{ CandidateRoot=$candidateRoot; ExpectedSourceSha=$head; ExpectedRuntimeProfile=$RuntimeProfile }
if ($AllowDirty) { $verifyArgs.AllowDirtySource = $true }
& $verifier @verifyArgs | Out-Null

Write-Host ''
Write-Host 'GEMMAMONSTER STABLE 2026.4 CANDIDATE BUILT'
Write-Host "  SOURCE_SHA:       $head"
Write-Host "  BRANCH:           $branch"
Write-Host "  RUNTIME_PROFILE:  $RuntimeProfile"
Write-Host "  DEP_ROOT:         C:\$ShortRoot"
Write-Host "  CANDIDATE_ROOT:   $candidateRoot"
Write-Host "  OVMS_SHA256:      $($manifest.package.ovms_sha256)"
Write-Host "  MANIFEST:         $manifestPath"
Write-Host "  VERSION_EVIDENCE: $versionLog"
Write-Host ('  STATUS:           ' + $(if ($dirty) { 'BUILT_DIRTY_NOT_ACCEPTABLE' } else { 'BUILT_PROVENANCE_VERIFIED_NOT_ACCEPTED' }))
