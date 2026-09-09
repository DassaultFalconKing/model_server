[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [string]$DependencyRootName = 'g5',
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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
$gemma = Join-Path $package 'gemma4'
$profile = Join-Path $gemma 'profile-E'
New-Item -ItemType Directory -Path $profile -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'runtime\gemmamonster-ovms-E\profile.json') -Destination $profile
Copy-Item -LiteralPath (Join-Path $root 'runtime\gemmamonster-ovms-E\README.md') -Destination $profile
Copy-Item -LiteralPath (Join-Path $root 'scripts\gemma4\Start-Gemma4.ps1') -Destination $gemma

$gitSha = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $gitSha -notmatch '^[0-9a-f]{40}$') { throw 'Cannot resolve exact package git SHA.' }
$binary = Join-Path $package 'ovms.exe'
$provenance = [ordered]@{
    schema_version = 1
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    git_sha = $gitSha
    branch = (& git -C $root branch --show-current).Trim()
    ovms_sha256 = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()
    profile = 'E'
    model_weights_included = $false
    model_path_policy = 'External path supplied to gemma4/Start-Gemma4.ps1 -ModelPath'
    standard_package_builder = 'windows_create_package.bat'
    dependency_root = "C:\$DependencyRootName"
}
$provenance | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $gemma 'PACKAGE-PROVENANCE.json') -Encoding UTF8

$manifest = Join-Path $package 'SHA256SUMS'
$files = Get-ChildItem -LiteralPath $package -Recurse -File | Where-Object { $_.FullName -ne $manifest } | Sort-Object FullName
$lines = foreach ($file in $files) {
    $relative = [System.IO.Path]::GetRelativePath($package, $file.FullName).Replace('\', '/')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $relative"
}
$lines | Set-Content -LiteralPath $manifest -Encoding ascii

$zip = Join-Path $output ("ovms-gemma4-2026.5-" + $gitSha.Substring(0, 8) + '-windows.zip')
& C:\Windows\System32\tar.exe -a -c -f $zip -C $output ovms
if ($LASTEXITCODE -ne 0) { throw "Archive creation failed with exit code $LASTEXITCODE" }

[ordered]@{package_root=$package;archive=$zip;git_sha=$gitSha;files=$files.Count;archive_sha256=(Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()} |
    ConvertTo-Json -Depth 4 | Write-Host
