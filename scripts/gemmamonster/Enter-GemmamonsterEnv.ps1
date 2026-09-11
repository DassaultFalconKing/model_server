[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [switch]$AllowDirty,
    [switch]$RequireRuntimeRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Canonical Gemmamonster 2026.4 maintainer-RC2 build environment.
# This script intentionally changes PROCESS-SCOPE environment only.
# Run it in the same PowerShell process that will perform dependency install,
# build, test, package, or runtime acceptance. Do not launch it through a
# separate `powershell.exe -File ...` process and expect the environment to
# survive after that process exits.
$canonical = [ordered]@{
    BAZEL_VERSION = '6.1.1'
    BAZEL_VS = 'C:\BuildTools'
    BAZEL_VC = 'C:\BuildTools\VC'
    BAZEL_VC_FULL_VERSION = '14.44.35207'
    BAZEL_SH = 'C:\opt\msys64\usr\bin\bash.exe'
    PYTHONHOME = 'C:\opt\Python312'
    PYTHON_VERSION = '3.12.10'
    GEMMAMONSTER_ROOT = 'C:\g54r2'
    OpenVINO_DIR = 'C:\g54r2\openvino\runtime\cmake'
    OpenCV_DIR = 'C:\opt\opencv_4.14.0'
    OV_SOURCE_BRANCH = '227c33757d1ef95d4da506d00686f923fdd2a535'
    OV_TOKENIZERS_BRANCH = 'a04accf6282d9b304214b492694b18c3979f667a'
    OV_GENAI_BRANCH = '7ea2546852a382cd16bd22dea0cfad2db70ed744'
    GENAI_PACKAGE_URL_WINDOWS = 'https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/pre-release/2026.4.0.0rc2/openvino_genai_windows_2026.4.0.0rc2_x86_64.zip'
}

function Remove-ProcessEnv([string]$Name) {
    if (Test-Path -LiteralPath "Env:$Name") {
        Remove-Item -LiteralPath "Env:$Name" -ErrorAction Stop
    }
}

function Test-StalePathEntry([string]$Entry, [string[]]$LegacyRoots) {
    if ([string]::IsNullOrWhiteSpace($Entry)) { return $true }
    $path = $Entry.Trim().Trim('"').Replace('/', '\').TrimEnd('\')
    if (-not $path) { return $true }

    foreach ($root in $LegacyRoots) {
        if ($root -and $path.StartsWith($root.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    # Re-add these canonical tool paths exactly once after sanitization.
    if ($path -ieq 'C:\opt') { return $true }
    if ($path -match '(?i)^C:\\opt\\Python3\d+(?:\\|$)') { return $true }
    if ($path -match '(?i)^C:\\opt\\msys64(?:\\|$)') { return $true }

    # Never inherit OpenVINO / GenAI / packaged OVMS runtime directories from a
    # previous build or acceptance process. Runtime provenance must be explicit.
    if ($path -match '(?i)\\openvino(?:[._-]genai)?(?:\\|$)') { return $true }
    if ($path -match '(?i)\\gemmamonster-artifacts\\') { return $true }
    if ($path -match '(?i)\\candidates\\.*\\ovms(?:\\|$)') { return $true }

    # Remove old Gemmamonster short roots (g54r1, g54r2, experiments, etc.).
    if ($path -match '(?i)^C:\\g54[^\\]*(?:\\|$)') { return $true }

    return $false
}

function Add-UniquePathEntry([System.Collections.Generic.List[string]]$List, [string]$Entry) {
    if ([string]::IsNullOrWhiteSpace($Entry)) { return }
    foreach ($existing in $List) {
        if ($existing -ieq $Entry) { return }
    }
    $List.Add($Entry)
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $root '.git')) -and
    -not (& git.exe -C $root rev-parse --is-inside-work-tree 2>$null)) {
    throw "Not a Git worktree: $root"
}

# Capture virtual/conda roots before clearing their marker variables so their
# PATH entries can be removed too.
$legacyRoots = @()
foreach ($name in @('VIRTUAL_ENV','CONDA_PREFIX','OVMS_DIR','GEMMAMONSTER_ROOT','OpenVINO_DIR','OPENVINO_DIR')) {
    $value = [Environment]::GetEnvironmentVariable($name, 'Process')
    if (-not [string]::IsNullOrWhiteSpace($value)) { $legacyRoots += $value }
}

# PHASE 1: SANITIZE. Remove all known build/runtime selectors from this process.
# Prefix families are intentionally narrow: this is a Gemmamonster shell reset,
# not a machine-wide environment purge.
$prefixes = @('OV_', 'GENAI_', 'OPENVINO_', 'GEMMAMONSTER_', 'BAZEL_')
$exactNames = @(
    'OpenVINO_DIR', 'OpenCV_DIR', 'OPENVINO_TOKENIZERS_PATH_GENAI',
    'PYTHONHOME', 'PYTHONPATH', 'PYTHONUSERBASE', 'PYTHONNOUSERSITE',
    'CMAKE_PREFIX_PATH', 'TBBROOT', 'TBB_DIR', 'OVMS_DIR',
    'VIRTUAL_ENV', 'CONDA_PREFIX', 'CONDA_DEFAULT_ENV'
)

foreach ($entry in @(Get-ChildItem Env:)) {
    $name = [string]$entry.Name
    if ($exactNames -contains $name) {
        Remove-ProcessEnv $name
        continue
    }
    foreach ($prefix in $prefixes) {
        if ($name.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-ProcessEnv $name
            break
        }
    }
}

$cleanPath = [System.Collections.Generic.List[string]]::new()
foreach ($entry in (($env:PATH -split ';') | Where-Object { $_ -ne $null })) {
    if (-not (Test-StalePathEntry -Entry $entry -LegacyRoots $legacyRoots)) {
        Add-UniquePathEntry -List $cleanPath -Entry $entry.Trim().Trim('"')
    }
}

# Assert that sanitation actually removed the selectors before setting new ones.
$leftovers = @()
foreach ($entry in @(Get-ChildItem Env:)) {
    $name = [string]$entry.Name
    if ($exactNames -contains $name) { $leftovers += $name; continue }
    foreach ($prefix in $prefixes) {
        if ($name.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $leftovers += $name
            break
        }
    }
}
if ($leftovers.Count -gt 0) {
    throw "Environment sanitation failed; stale selectors remain: $($leftovers -join ', ')"
}

# PHASE 2: INITIALIZE the one accepted maintainer-RC2 environment.
$env:BAZEL_VS = $canonical.BAZEL_VS
$env:BAZEL_VC = $canonical.BAZEL_VC
$env:BAZEL_VC_FULL_VERSION = $canonical.BAZEL_VC_FULL_VERSION
$env:BAZEL_SH = $canonical.BAZEL_SH
$env:PYTHONHOME = $canonical.PYTHONHOME
$env:GEMMAMONSTER_ROOT = $canonical.GEMMAMONSTER_ROOT
$env:OpenVINO_DIR = $canonical.OpenVINO_DIR
$env:OpenCV_DIR = $canonical.OpenCV_DIR
$env:OV_SOURCE_BRANCH = $canonical.OV_SOURCE_BRANCH
$env:OV_TOKENIZERS_BRANCH = $canonical.OV_TOKENIZERS_BRANCH
$env:OV_GENAI_BRANCH = $canonical.OV_GENAI_BRANCH
$env:GENAI_PACKAGE_URL_WINDOWS = $canonical.GENAI_PACKAGE_URL_WINDOWS
$env:GENAI_PACKAGE_URL = $canonical.GENAI_PACKAGE_URL_WINDOWS
$env:OV_USE_BINARY = '1'

$finalPath = [System.Collections.Generic.List[string]]::new()
foreach ($entry in @('C:\opt', 'C:\opt\Python312', 'C:\opt\Python312\Scripts', 'C:\opt\msys64\usr\bin')) {
    Add-UniquePathEntry -List $finalPath -Entry $entry
}
foreach ($entry in $cleanPath) { Add-UniquePathEntry -List $finalPath -Entry $entry }
$env:PATH = $finalPath -join ';'

# PHASE 3: VERIFY source identity, exact pin authority, and actual resolved tools.
$head = (& git.exe -C $root rev-parse HEAD).Trim()
$tree = (& git.exe -C $root rev-parse "$head^{tree}").Trim()
$branch = (& git.exe -C $root branch --show-current).Trim()
$dirtyLines = @(& git.exe -C $root status --porcelain)
if ($dirtyLines.Count -gt 0 -and -not $AllowDirty) {
    throw "Working tree is dirty after environment initialization. Refusing preflight.`n$($dirtyLines -join "`n")"
}

$bazelVersionFile = Join-Path $root '.bazelversion'
if (-not (Test-Path -LiteralPath $bazelVersionFile -PathType Leaf)) { throw "Missing .bazelversion: $bazelVersionFile" }
$declaredBazel = (Get-Content -LiteralPath $bazelVersionFile -Raw -Encoding UTF8).Trim()
if ($declaredBazel -ne $canonical.BAZEL_VERSION) {
    throw "Wrong repository Bazel version: expected=$($canonical.BAZEL_VERSION) actual=$declaredBazel"
}

$bazelCommand = Get-Command bazel.exe -ErrorAction SilentlyContinue
if ($null -eq $bazelCommand) { $bazelCommand = Get-Command bazel -ErrorAction Stop }
$bazelText = (& $bazelCommand.Source --version 2>&1 | Out-String).Trim()
if ($bazelText -notmatch "(?<!\d)$([regex]::Escape($canonical.BAZEL_VERSION))(?!\d)") {
    throw "Wrong active Bazel: expected $($canonical.BAZEL_VERSION), got '$bazelText' from $($bazelCommand.Source)"
}

$pythonExe = Join-Path $canonical.PYTHONHOME 'python.exe'
if (-not (Test-Path -LiteralPath $pythonExe -PathType Leaf)) { throw "Canonical Python missing: $pythonExe" }
$pythonText = (& $pythonExe --version 2>&1 | Out-String).Trim()
if ($pythonText -notmatch "Python\s+$([regex]::Escape($canonical.PYTHON_VERSION))(?:\s|$)") {
    throw "Wrong canonical Python: expected=$($canonical.PYTHON_VERSION) actual='$pythonText'"
}
if (-not (Test-Path -LiteralPath $canonical.BAZEL_SH -PathType Leaf)) { throw "Canonical MSYS bash missing: $($canonical.BAZEL_SH)" }
if (-not (Test-Path -LiteralPath $canonical.BAZEL_VS -PathType Container)) { throw "Canonical VS Build Tools missing: $($canonical.BAZEL_VS)" }

$versionsPath = Join-Path $root 'versions.mk'
if (-not (Test-Path -LiteralPath $versionsPath -PathType Leaf)) { throw "Missing versions.mk: $versionsPath" }
$versionsText = Get-Content -LiteralPath $versionsPath -Raw -Encoding UTF8
foreach ($pair in @(
    @('OV_SOURCE_BRANCH', $canonical.OV_SOURCE_BRANCH),
    @('OV_TOKENIZERS_BRANCH', $canonical.OV_TOKENIZERS_BRANCH),
    @('OV_GENAI_BRANCH', $canonical.OV_GENAI_BRANCH),
    @('GENAI_PACKAGE_URL_WINDOWS', $canonical.GENAI_PACKAGE_URL_WINDOWS)
)) {
    $name = [string]$pair[0]
    $value = [string]$pair[1]
    if ($versionsText -notmatch "(?m)^$([regex]::Escape($name))\s*\?=\s*$([regex]::Escape($value))\s*$") {
        throw "versions.mk authority mismatch for ${name}: expected '$value'"
    }
}
if ($versionsText -match '2026\.5') { throw 'versions.mk contains a 2026.5 marker; refusing 2026.4 acceptance environment.' }

$runtimeRoot = Join-Path $canonical.GEMMAMONSTER_ROOT 'openvino'
$runtimeReady = Test-Path -LiteralPath $runtimeRoot -PathType Container
if ($RequireRuntimeRoot -and -not $runtimeReady) {
    throw "Canonical runtime root is missing: $runtimeRoot. Bootstrap dependencies first in this same sanitized shell."
}

# Reject any runtime/build selector that disagrees with the canonical values.
$assertions = [ordered]@{
    BAZEL_VS = $canonical.BAZEL_VS
    BAZEL_VC = $canonical.BAZEL_VC
    BAZEL_VC_FULL_VERSION = $canonical.BAZEL_VC_FULL_VERSION
    BAZEL_SH = $canonical.BAZEL_SH
    PYTHONHOME = $canonical.PYTHONHOME
    GEMMAMONSTER_ROOT = $canonical.GEMMAMONSTER_ROOT
    OpenVINO_DIR = $canonical.OpenVINO_DIR
    OpenCV_DIR = $canonical.OpenCV_DIR
    OV_SOURCE_BRANCH = $canonical.OV_SOURCE_BRANCH
    OV_TOKENIZERS_BRANCH = $canonical.OV_TOKENIZERS_BRANCH
    OV_GENAI_BRANCH = $canonical.OV_GENAI_BRANCH
    GENAI_PACKAGE_URL_WINDOWS = $canonical.GENAI_PACKAGE_URL_WINDOWS
    GENAI_PACKAGE_URL = $canonical.GENAI_PACKAGE_URL_WINDOWS
    OV_USE_BINARY = '1'
}
foreach ($name in $assertions.Keys) {
    $actual = [Environment]::GetEnvironmentVariable([string]$name, 'Process')
    $expected = [string]$assertions[$name]
    if ($actual -ne $expected) { throw "Environment assertion failed for ${name}: expected='$expected' actual='$actual'" }
}

$summary = [pscustomobject]@{
    ENV_PREFLIGHT = 'PASS'
    BRANCH = $branch
    SOURCE_HEAD = $head
    SOURCE_TREE = $tree
    WORKTREE = if ($dirtyLines.Count -eq 0) { 'CLEAN' } else { 'DIRTY_ALLOWED' }
    BAZEL = $bazelText
    BAZEL_PATH = $bazelCommand.Source
    PYTHON = $pythonText
    PYTHON_PATH = $pythonExe
    RUNTIME_ROOT = $runtimeRoot
    RUNTIME_ROOT_STATE = if ($runtimeReady) { 'READY' } else { 'NOT_BOOTSTRAPPED' }
    OPENVINO_SHA = $canonical.OV_SOURCE_BRANCH
    GENAI_SHA = $canonical.OV_GENAI_BRANCH
    TOKENIZERS_SHA = $canonical.OV_TOKENIZERS_BRANCH
    RUNTIME_PROFILE = 'maintainer-rc2'
}

Write-Host 'GEMMAMONSTER ENV PRE-FLIGHT PASS'
$summary | Format-List
$summary
