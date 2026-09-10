[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [string]$DependencyRootName = 'opt',
    [string]$OvmsLine = '2026.5',
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Sha256Manifest {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [string[]]$ExcludePrefixes = @(),
        [string[]]$ExcludeRelative = @()
    )

    $base = (Resolve-Path -LiteralPath $BasePath).Path
    $excludedFiles = @($ExcludeRelative | ForEach-Object { $_.Replace('\\', '/').TrimStart('/') })
    $lines = foreach ($file in Get-ChildItem -LiteralPath $base -Recurse -File | Sort-Object FullName) {
        $relative = [System.IO.Path]::GetRelativePath($base, $file.FullName).Replace('\\', '/')
        if ($excludedFiles -contains $relative) { continue }
        $skip = $false
        foreach ($prefix in $ExcludePrefixes) {
            $normalizedPrefix = $prefix.Replace('\\', '/').Trim('/') + '/'
            if ($relative.StartsWith($normalizedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $skip = $true
                break
            }
        }
        if ($skip) { continue }
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
    $lines | Set-Content -LiteralPath $OutputPath -Encoding ascii
}

function Get-VersionValue {
    param(
        [Parameter(Mandatory = $true)][string]$VersionsText,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($VersionsText -match "(?m)^$([Regex]::Escape($Name))\s+\?=\s+([^\s]+)") {
        return $Matches[1]
    }
    return $null
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$output = [System.IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $output) { throw "OutputRoot already exists; refusing to overwrite: $output" }
New-Item -ItemType Directory -Path $output | Out-Null

$packageBat = Join-Path $root 'windows_create_package.bat'
Push-Location $root
try {
    & cmd.exe /d /c "`"$packageBat`" $DependencyRootName --with_python `"$output`""
    if ($LASTEXITCODE -ne 0) { throw "Standard Windows package creation failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}

$package = Join-Path $output 'ovms'
if (-not (Test-Path -LiteralPath $package -PathType Container)) {
    throw "Standard Windows package builder did not create expected runtime directory: $package"
}

# windows_create_package.bat creates ovms.zip before GEMMAMONSTER metadata is added.
# That archive is intentionally removed so no stale archive can be mistaken for the
# immutable candidate archive produced below.
$staleArchive = Join-Path $output 'ovms.zip'
if (Test-Path -LiteralPath $staleArchive -PathType Leaf) {
    Remove-Item -LiteralPath $staleArchive -Force
}

$gemma = Join-Path $package 'gemma4'
$profile = Join-Path $gemma 'profile-E'
New-Item -ItemType Directory -Path $profile -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'runtime\gemmamonster-ovms-E\profile.json') -Destination $profile
$profileReadme = Join-Path $root 'runtime\gemmamonster-ovms-E\README.md'
if (Test-Path -LiteralPath $profileReadme -PathType Leaf) {
    Copy-Item -LiteralPath $profileReadme -Destination $profile
}
$gemmaReadme = Join-Path $root 'scripts\gemma4\README.md'
if (Test-Path -LiteralPath $gemmaReadme -PathType Leaf) {
    Copy-Item -LiteralPath $gemmaReadme -Destination $gemma
}
Copy-Item -LiteralPath (Join-Path $root 'scripts\gemma4\Start-Gemma4.ps1') -Destination $gemma
$contractDoc = Join-Path $root 'docs\gemmamonster\CANDIDATE-ARTIFACT-CONTRACT.md'
if (Test-Path -LiteralPath $contractDoc -PathType Leaf) {
    Copy-Item -LiteralPath $contractDoc -Destination $gemma
}

$gitSha = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $gitSha -notmatch '^[0-9a-f]{40}$') { throw 'Cannot resolve exact package git SHA.' }
$branch = (& git -C $root branch --show-current).Trim()
$binary = Join-Path $package 'ovms.exe'
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw "Packaged ovms.exe is missing: $binary" }
$ovmsSha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()

$versionsPath = Join-Path $root 'versions.mk'
$versionsText = Get-Content -LiteralPath $versionsPath -Raw -Encoding UTF8
$versions = [ordered]@{
    openvino_source = Get-VersionValue -VersionsText $versionsText -Name 'OV_SOURCE_BRANCH'
    openvino_genai = Get-VersionValue -VersionsText $versionsText -Name 'OV_GENAI_BRANCH'
    openvino_tokenizers = Get-VersionValue -VersionsText $versionsText -Name 'OV_TOKENIZERS_BRANCH'
    opencv = Get-VersionValue -VersionsText $versionsText -Name 'OPENCV_VERSION'
    curl = Get-VersionValue -VersionsText $versionsText -Name 'CURL_VERSION'
}

$provenanceDir = Join-Path $output 'provenance'
$acceptanceDir = Join-Path $output 'acceptance'
$logsDir = Join-Path $output 'logs'
$dumpsDir = Join-Path $output 'dumps'
foreach ($dir in @($provenanceDir, $acceptanceDir, $logsDir, $dumpsDir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

$buildLogSource = Join-Path $root 'win_incremental_build.log'
$buildLogRelative = $null
if (Test-Path -LiteralPath $buildLogSource -PathType Leaf) {
    $buildLogDestination = Join-Path $logsDir 'build.log'
    Copy-Item -LiteralPath $buildLogSource -Destination $buildLogDestination
    $buildLogRelative = 'logs/build.log'
}

$sourceProvenance = [ordered]@{
    schema_version = 1
    git_sha = $gitSha
    branch = $branch
    repository = 'DassaultFalconKing/model_server'
    versions_mk_sha256 = (Get-FileHash -LiteralPath $versionsPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
$sourceProvenance | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $provenanceDir 'source.json') -Encoding UTF8

$buildProvenance = [ordered]@{
    schema_version = 1
    bazel_target = '//src:ovms'
    bazel_config = 'win_mp_on_py_off'
    dependency_root = "C:\$DependencyRootName"
    openvino_dir = "C:\$DependencyRootName\openvino\runtime\cmake"
    standard_package_builder = 'windows_create_package.bat'
    build_log = $buildLogRelative
}
$buildProvenance | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $provenanceDir 'build.json') -Encoding UTF8

$runtimeProvenance = [ordered]@{
    schema_version = 1
    entrypoint = 'ovms/ovms.exe'
    runtime_policy = 'SELF_CONTAINED_PACKAGE_ONLY'
    external_runtime_dlls_allowed = $false
    model_weights_included = $false
    model_path_policy = 'External path supplied to gemma4/Start-Gemma4.ps1 -ModelPath'
}
$runtimeProvenance | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $provenanceDir 'runtime.json') -Encoding UTF8

$dependencyFiles = @(Get-ChildItem -LiteralPath $package -File | Where-Object { $_.Extension -ieq '.dll' } | Sort-Object Name)
$dependencyRecords = foreach ($file in $dependencyFiles) {
    [ordered]@{
        name = $file.Name
        relative_path = ('ovms/' + $file.Name)
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        size = $file.Length
        file_version = $file.VersionInfo.FileVersion
        product_version = $file.VersionInfo.ProductVersion
    }
}
$dependencyProvenance = [ordered]@{
    schema_version = 1
    dependency_root = "C:\$DependencyRootName"
    versions = $versions
    files = @($dependencyRecords)
}
$dependencyProvenance | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $provenanceDir 'dependencies.json') -Encoding UTF8

# Preserve package-local provenance for users who receive only the release-like ovms directory.
$packageProvenance = [ordered]@{
    schema_version = 2
    contract = 'gemmamonster-candidate-v1'
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    git_sha = $gitSha
    branch = $branch
    ovms_sha256 = $ovmsSha256
    profile = 'E'
    model_weights_included = $false
    model_path_policy = 'External path supplied to gemma4/Start-Gemma4.ps1 -ModelPath'
    standard_package_builder = 'windows_create_package.bat'
    dependency_root = "C:\$DependencyRootName"
    runtime_policy = 'SELF_CONTAINED_PACKAGE_ONLY'
}
$packageProvenance | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $gemma 'PACKAGE-PROVENANCE.json') -Encoding UTF8

# Rebuild the package-local manifest after all GEMMAMONSTER additions are present.
$packageManifest = Join-Path $package 'SHA256SUMS'
Write-Sha256Manifest -BasePath $package -OutputPath $packageManifest -ExcludeRelative @('SHA256SUMS')

$archiveName = "ovms-gemma4-$OvmsLine-$($gitSha.Substring(0, 8))-windows.zip"
$archive = Join-Path $output $archiveName
& C:\Windows\System32\tar.exe -a -c -f $archive -C $output ovms
if ($LASTEXITCODE -ne 0) { throw "Archive creation failed with exit code $LASTEXITCODE" }
$archiveSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()

$manifest = [ordered]@{
    schema_version = 1
    contract = 'gemmamonster-candidate-v1'
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    candidate_id = "$OvmsLine-$($gitSha.Substring(0, 8))"
    ovms_line = $OvmsLine
    source = [ordered]@{
        git_sha = $gitSha
        branch = $branch
    }
    package = [ordered]@{
        root = 'ovms'
        entrypoint = 'ovms/ovms.exe'
        ovms_sha256 = $ovmsSha256
        package_sha256_manifest = 'ovms/SHA256SUMS'
        archive = $archiveName
        archive_sha256 = $archiveSha256
    }
    provenance = [ordered]@{
        source = 'provenance/source.json'
        build = 'provenance/build.json'
        runtime = 'provenance/runtime.json'
        dependencies = 'provenance/dependencies.json'
    }
    evidence = [ordered]@{
        acceptance = 'acceptance'
        logs = 'logs'
        dumps = 'dumps'
    }
}
$manifestPath = Join-Path $output 'manifest.json'
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

# Root manifest covers the immutable candidate payload only. Runtime evidence directories
# remain writable so acceptance logs/dumps can be added without invalidating the candidate.
$rootShaManifest = Join-Path $output 'SHA256SUMS.txt'
Write-Sha256Manifest -BasePath $output -OutputPath $rootShaManifest -ExcludePrefixes @('acceptance', 'logs', 'dumps') -ExcludeRelative @('SHA256SUMS.txt')

$verifyScript = Join-Path $root 'scripts\gemma4\Test-CandidateArtifact.ps1'
$verified = & $verifyScript -CandidateRoot $output -ExpectedGitSha $gitSha

[ordered]@{
    contract = $verified.Contract
    candidate_root = $output
    package_root = $package
    archive = $archive
    git_sha = $gitSha
    ovms_sha256 = $ovmsSha256
    archive_sha256 = $archiveSha256
    package_files = (Get-ChildItem -LiteralPath $package -Recurse -File).Count
    root_manifest_entries = $verified.RootManifestEntries
} | ConvertTo-Json -Depth 6 | Write-Host
