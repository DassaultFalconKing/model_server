[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$ExpectedGitSha
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $PackageRoot).Path
$required = @(
    'ovms.exe',
    'openvino.dll',
    'openvino_genai.dll',
    'openvino_tokenizers.dll',
    'tbb12.dll',
    'setupvars.bat',
    'LICENSE',
    'thirdparty-licenses',
    'python\python.exe',
    'gemma4\profile-E\profile.json',
    'gemma4\Start-Gemma4.ps1',
    'gemma4\PACKAGE-PROVENANCE.json',
    'SHA256SUMS'
)

foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relative))) {
        throw "Missing required package entry: $relative"
    }
}

$provenance = Get-Content -LiteralPath (Join-Path $root 'gemma4\PACKAGE-PROVENANCE.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($provenance.git_sha -ne $ExpectedGitSha) {
    throw "Package git SHA mismatch: expected=$ExpectedGitSha actual=$($provenance.git_sha)"
}

$manifestPath = Join-Path $root 'SHA256SUMS'
$manifestLines = @(Get-Content -LiteralPath $manifestPath -Encoding UTF8 | Where-Object { $_ })
if ($manifestLines.Count -lt 10) { throw 'SHA256SUMS is unexpectedly small.' }
foreach ($line in $manifestLines) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw "Malformed SHA256SUMS line: $line" }
    $expected = $Matches[1]
    $relative = $Matches[2].Replace('/', '\')
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Manifest entry missing: $relative" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Hash mismatch: $relative" }
}

& (Join-Path $root 'ovms.exe') --version | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Packaged ovms.exe --version failed.' }
& (Join-Path $root 'ovms.exe') --help | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Packaged ovms.exe --help failed.' }

Write-Host "GEMMA4_STANDALONE_PACKAGE_TEST_PASS root=$root files=$($manifestLines.Count)"
