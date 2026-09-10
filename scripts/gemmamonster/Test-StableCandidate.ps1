[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CandidateRoot,
    [string]$ExpectedSourceSha = '',
    [ValidateSet('','maintainer-rc2','known-good-rc1')][string]$ExpectedRuntimeProfile = '',
    [switch]$AllowDirtySource
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'stable-runtime-profiles.ps1')

function Require-File([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing required runtime file (${Label}): $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Read-Manifest([string]$Path) {
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "Invalid candidate manifest JSON: $Path. $($_.Exception.Message)"
    }
}

function Assert-ExactPin([object]$Pins, [string]$Name, [string]$Expected) {
    $property = $Pins.PSObject.Properties[$Name]
    if ($null -eq $property) { throw "Dependency pin missing: $Name" }
    $actual = [string]$property.Value
    if ($actual -ne $Expected) {
        throw "Dependency pin mismatch for ${Name}: expected=$Expected actual=$actual"
    }
}

function Assert-HashManifest([string]$Root, [string]$ShaFile) {
    $lines = @(Get-Content -LiteralPath $ShaFile -Encoding ASCII | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -lt 5) { throw "SHA256SUMS.txt is unexpectedly small: $($lines.Count) entries" }
    foreach ($line in $lines) {
        if ($line -notmatch '^([0-9a-fA-F]{64})\s+(.+)$') { throw "Malformed SHA256SUMS line: $line" }
        $expected = $Matches[1].ToLowerInvariant()
        $relative = $Matches[2].Trim().Replace('/','\')
        $path = Join-Path $Root $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Manifest entry missing: $relative" }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $expected) { throw "Hash mismatch: $relative expected=$expected actual=$actual" }
    }
}

$root = (Resolve-Path -LiteralPath $CandidateRoot).Path
$manifestPath = Require-File (Join-Path $root 'manifest.json') 'manifest.json'
$shaPath = Require-File (Join-Path $root 'SHA256SUMS.txt') 'SHA256SUMS.txt'
$manifest = Read-Manifest $manifestPath

if ([int]$manifest.schema_version -ne 2) {
    throw "Unsupported candidate manifest schema: expected=2 actual=$($manifest.schema_version)"
}
if ([string]$manifest.project -ne 'GEMMAMONSTER') {
    throw "Wrong candidate project: $($manifest.project)"
}
if ([string]$manifest.candidate_kind -ne 'stable-2026.4-refit') {
    throw "Wrong candidate_kind: expected=stable-2026.4-refit actual=$($manifest.candidate_kind)"
}

$runtimeProfile = [string]$manifest.runtime_profile
if ($runtimeProfile -notin @('maintainer-rc2','known-good-rc1')) {
    throw "Unsupported runtime_profile in manifest: $runtimeProfile"
}
if ($ExpectedRuntimeProfile -and $runtimeProfile -ne $ExpectedRuntimeProfile) {
    throw "Runtime profile mismatch: expected=$ExpectedRuntimeProfile actual=$runtimeProfile"
}
$profile = Get-GemmamonsterStableRuntimeProfile -Name $runtimeProfile

$sourceSha = [string]$manifest.source_sha
if ($sourceSha -notmatch '^[0-9a-f]{40}$') { throw "Invalid source_sha in manifest: $sourceSha" }
if ($ExpectedSourceSha -and $sourceSha -ne $ExpectedSourceSha) {
    throw "Source SHA mismatch: expected=$ExpectedSourceSha actual=$sourceSha"
}
if ([bool]$manifest.repo_dirty -and -not $AllowDirtySource) {
    throw 'Candidate manifest records repo_dirty=true. Refusing provenance acceptance.'
}

$pins = $manifest.dependency_pins
if ($null -eq $pins) { throw 'Candidate manifest is missing dependency_pins.' }
Assert-ExactPin $pins 'OV_SOURCE_BRANCH' $profile.OV_SOURCE_BRANCH
Assert-ExactPin $pins 'OV_TOKENIZERS_BRANCH' $profile.OV_TOKENIZERS_BRANCH
Assert-ExactPin $pins 'OV_GENAI_BRANCH' $profile.OV_GENAI_BRANCH
Assert-ExactPin $pins 'GENAI_PACKAGE_URL_WINDOWS' $profile.GENAI_PACKAGE_URL_WINDOWS

$tooling = $manifest.tooling
if ($null -eq $tooling) { throw 'Candidate manifest is missing tooling pins.' }
foreach ($pin in @(
    @('python','PYTHON_VERSION'),
    @('optimum','OPTIMUM_VERSION'),
    @('optimum_intel','OPTIMUM_INTEL_VERSION'),
    @('openvino','OPTIMUM_OPENVINO_VERSION'),
    @('openvino_tokenizers','OPTIMUM_OPENVINO_TOKENIZERS_VERSION')
)) {
    $actual = [string]$tooling.($pin[0])
    $expected = [string]$profile.($pin[1])
    if ($actual -ne $expected) { throw "Tooling pin mismatch for $($pin[0]): expected=$expected actual=$actual" }
}

$versionPath = Require-File (Join-Path $root 'provenance\ovms-version.txt') 'ovms-version.txt'
$versionText = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8
$ovFingerprint = ([string]$profile.OV_SOURCE_BRANCH).Substring(0, 11)
$genaiFingerprint = ([string]$profile.OV_GENAI_BRANCH).Substring(0, 11)
if ($versionText -match '2026\.5') {
    throw "Runtime version fingerprint mismatch: stable candidate reports a 2026.5 component.`n$versionText"
}
if ($versionText -notmatch [regex]::Escape($ovFingerprint)) {
    throw "Runtime version fingerprint mismatch: expected OpenVINO SHA prefix $ovFingerprint for profile $runtimeProfile.`n$versionText"
}
if ($versionText -notmatch [regex]::Escape($genaiFingerprint)) {
    throw "Runtime version fingerprint mismatch: expected GenAI SHA prefix $genaiFingerprint for profile $runtimeProfile.`n$versionText"
}

$ovmsDir = Join-Path $root 'ovms'
foreach ($name in @('ovms.exe','openvino.dll','openvino_genai.dll','openvino_tokenizers.dll','tbb12.dll')) {
    Require-File (Join-Path $ovmsDir $name) $name | Out-Null
}
# optimum_bundled missing (old manifests) means bundled: early candidates always had it.
$optimumBundled = $true
$optimumFlag = $tooling.PSObject.Properties['optimum_bundled']
if ($null -ne $optimumFlag) { $optimumBundled = [bool]$optimumFlag.Value }
$requiredTooling = @('python\python.exe')
if ($optimumBundled) { $requiredTooling += 'tools\optimum\optimum-cli.cmd' }
foreach ($relative in $requiredTooling) {
    $path = Join-Path $ovmsDir $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required tooling file: $path" }
}

Assert-HashManifest $root $shaPath

$expectedOvms = [string]$manifest.package.ovms_sha256
$actualOvms = (Get-FileHash -LiteralPath (Join-Path $ovmsDir 'ovms.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
if (-not $expectedOvms -or $actualOvms -ne $expectedOvms.ToLowerInvariant()) {
    throw "Packaged ovms.exe hash mismatch: manifest=$expectedOvms actual=$actualOvms"
}

foreach ($name in @('openvino.dll','openvino_genai.dll','openvino_tokenizers.dll','tbb12.dll')) {
    $expectedProperty = $manifest.package.dll_sha256.PSObject.Properties[$name]
    if ($null -eq $expectedProperty) { throw "Manifest missing DLL hash: $name" }
    $expected = ([string]$expectedProperty.Value).ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath (Join-Path $ovmsDir $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "DLL hash mismatch: $name expected=$expected actual=$actual" }
}

[pscustomobject]@{
    status = 'PASS'
    candidate_root = $root
    source_sha = $sourceSha
    runtime_profile = $runtimeProfile
    ovms_sha256 = $actualOvms
    openvino_fingerprint = $ovFingerprint
    genai_fingerprint = $genaiFingerprint
    dependency_pins = $pins
}
