[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CandidateRoot,
    [string]$ExpectedGitSha = '',
    [switch]$VerifyLoadedRuntime
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-ContainedPath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "Artifact path must be relative: $RelativePath"
    }
    $normalized = $RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar).Replace('\\', [System.IO.Path]::DirectorySeparatorChar)
    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $base $normalized))
    $prefix = $base + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -and -not $resolved.Equals($base, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Artifact path escapes candidate root: $RelativePath"
    }
    return $resolved
}

function Test-Sha256Manifest {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [string[]]$ForbiddenPrefixes = @()
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "SHA256 manifest not found: $ManifestPath"
    }

    $lines = @(Get-Content -LiteralPath $ManifestPath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -eq 0) { throw "SHA256 manifest is empty: $ManifestPath" }

    foreach ($line in $lines) {
        if ($line -notmatch '^([0-9a-fA-F]{64})  (.+)$') {
            throw "Malformed SHA256 manifest line in ${ManifestPath}: $line"
        }
        $expected = $Matches[1].ToLowerInvariant()
        $relative = $Matches[2].Replace('\\', '/').TrimStart('/')
        foreach ($prefix in $ForbiddenPrefixes) {
            $normalizedPrefix = $prefix.Replace('\\', '/').Trim('/') + '/'
            if ($relative.StartsWith($normalizedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Mutable evidence path must not be part of immutable SHA256 manifest: $relative"
            }
        }
        $path = Resolve-ContainedPath -BasePath $BasePath -RelativePath $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "SHA256 manifest entry missing: $relative"
        }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) {
            throw "Hash mismatch for ${relative}: expected=$expected actual=$actual"
        }
    }
    return $lines.Count
}

$root = (Resolve-Path -LiteralPath $CandidateRoot).Path
$requiredRootEntries = @(
    'manifest.json',
    'SHA256SUMS.txt',
    'provenance\source.json',
    'provenance\build.json',
    'provenance\runtime.json',
    'provenance\dependencies.json',
    'acceptance',
    'logs',
    'dumps',
    'ovms\ovms.exe',
    'ovms\openvino.dll',
    'ovms\openvino_genai.dll',
    'ovms\openvino_tokenizers.dll',
    'ovms\tbb12.dll',
    'ovms\setupvars.bat',
    'ovms\SHA256SUMS'
)
foreach ($relative in $requiredRootEntries) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required candidate artifact entry: $relative"
    }
}

$manifestPath = Join-Path $root 'manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.contract -ne 'gemmamonster-candidate-v1') {
    throw "Unsupported candidate contract: $($manifest.contract)"
}
if ($manifest.schema_version -ne 1) {
    throw "Unsupported candidate schema_version: $($manifest.schema_version)"
}
$gitSha = [string]$manifest.source.git_sha
if ($gitSha -notmatch '^[0-9a-f]{40}$') {
    throw "Candidate manifest source git SHA is invalid: $gitSha"
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedGitSha) -and $gitSha -ne $ExpectedGitSha) {
    throw "Candidate git SHA mismatch: expected=$ExpectedGitSha actual=$gitSha"
}
if ([string]$manifest.package.root -ne 'ovms') {
    throw "Candidate package.root must be 'ovms': $($manifest.package.root)"
}
if ([string]$manifest.package.entrypoint -ne 'ovms/ovms.exe') {
    throw "Candidate package.entrypoint must be 'ovms/ovms.exe': $($manifest.package.entrypoint)"
}

$packageRoot = Join-Path $root 'ovms'
$ovmsExe = Join-Path $packageRoot 'ovms.exe'
$ovmsHash = (Get-FileHash -LiteralPath $ovmsExe -Algorithm SHA256).Hash.ToLowerInvariant()
if ([string]$manifest.package.ovms_sha256 -ne $ovmsHash) {
    throw "Candidate ovms.exe SHA256 mismatch: manifest=$($manifest.package.ovms_sha256) actual=$ovmsHash"
}

$source = Get-Content -LiteralPath (Join-Path $root 'provenance\source.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$source.git_sha -ne $gitSha) {
    throw "provenance/source.json git SHA mismatch: manifest=$gitSha provenance=$($source.git_sha)"
}
$runtime = Get-Content -LiteralPath (Join-Path $root 'provenance\runtime.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$runtime.entrypoint -ne 'ovms/ovms.exe') {
    throw "provenance/runtime.json entrypoint mismatch: $($runtime.entrypoint)"
}
if ([string]$runtime.runtime_policy -ne 'SELF_CONTAINED_PACKAGE_ONLY') {
    throw "provenance/runtime.json runtime_policy must be SELF_CONTAINED_PACKAGE_ONLY"
}

$dependencies = Get-Content -LiteralPath (Join-Path $root 'provenance\dependencies.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($dependency in @($dependencies.files)) {
    $relative = [string]$dependency.relative_path
    $path = Resolve-ContainedPath -BasePath $root -RelativePath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Dependency provenance entry missing: $relative"
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne [string]$dependency.sha256) {
        throw "Dependency SHA256 mismatch for ${relative}: expected=$($dependency.sha256) actual=$actual"
    }
}

$packageManifestCount = Test-Sha256Manifest -BasePath $packageRoot -ManifestPath (Join-Path $packageRoot 'SHA256SUMS')
$rootManifestCount = Test-Sha256Manifest -BasePath $root -ManifestPath (Join-Path $root 'SHA256SUMS.txt') -ForbiddenPrefixes @('acceptance', 'logs', 'dumps')

$verifiedProcessId = $null
if ($VerifyLoadedRuntime) {
    if (-not $IsWindows) { throw 'Loaded-runtime verification is supported only on Windows.' }
    $processMatches = @(
        Get-CimInstance Win32_Process -Filter "Name='ovms.exe'" |
            Where-Object { $_.ExecutablePath -and [System.IO.Path]::GetFullPath($_.ExecutablePath).Equals([System.IO.Path]::GetFullPath($ovmsExe), [System.StringComparison]::OrdinalIgnoreCase) }
    )
    if ($processMatches.Count -ne 1) {
        throw "Expected exactly one running ovms.exe from candidate entrypoint, found $($processMatches.Count): $ovmsExe"
    }
    $verifiedProcessId = [int]$processMatches[0].ProcessId
    try {
        $modules = @(Get-Process -Id $verifiedProcessId -ErrorAction Stop | ForEach-Object { $_.Modules })
    } catch {
        throw "Cannot enumerate loaded modules for candidate ovms.exe PID=${verifiedProcessId}: $($_.Exception.Message)"
    }
    $tracked = @('openvino.dll', 'openvino_genai.dll', 'openvino_tokenizers.dll', 'tbb12.dll')
    $loadedTracked = @($modules | Where-Object { $tracked -contains $_.ModuleName.ToLowerInvariant() })
    $openvino = @($loadedTracked | Where-Object { $_.ModuleName -ieq 'openvino.dll' })
    if ($openvino.Count -ne 1) {
        throw "Expected exactly one loaded openvino.dll in candidate process, found $($openvino.Count)."
    }
    foreach ($module in $loadedTracked) {
        $modulePath = [System.IO.Path]::GetFullPath($module.FileName)
        $packagePrefix = [System.IO.Path]::GetFullPath($packageRoot).TrimEnd('\\') + '\\'
        if (-not $modulePath.StartsWith($packagePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Candidate process loaded runtime module outside package: $($module.ModuleName) => $modulePath"
        }
    }
}

[PSCustomObject]@{
    Contract = 'gemmamonster-candidate-v1'
    GitSha = $gitSha
    Branch = [string]$manifest.source.branch
    CandidateRoot = $root
    PackageRoot = $packageRoot
    OvmsExe = $ovmsExe
    OvmsSha256 = $ovmsHash
    ManifestPath = $manifestPath
    PackageManifestEntries = $packageManifestCount
    RootManifestEntries = $rootManifestCount
    ProcessId = $verifiedProcessId
}
