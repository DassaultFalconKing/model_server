[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$verifier = Join-Path $repoRoot 'scripts\gemmamonster\Test-StableCandidate.ps1'
if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) {
    throw "RED: stable candidate verifier is missing: $verifier"
}

function Write-HashManifest([string]$CandidateRoot) {
    $lines = foreach ($file in Get-ChildItem -LiteralPath (Join-Path $CandidateRoot 'ovms') -Recurse -File | Sort-Object FullName) {
        $relative = [System.IO.Path]::GetRelativePath($CandidateRoot, $file.FullName).Replace('\\','/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
    $lines | Set-Content -LiteralPath (Join-Path $CandidateRoot 'SHA256SUMS.txt') -Encoding ASCII
}

function New-FakeCandidate([string]$Root, [string]$RuntimeProfile) {
    New-Item -ItemType Directory -Path (Join-Path $Root 'ovms') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root 'ovms\python') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root 'ovms\tools\optimum\site-packages') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root 'provenance') -Force | Out-Null
    foreach ($name in @('ovms.exe','openvino.dll','openvino_genai.dll','openvino_tokenizers.dll','tbb12.dll')) {
        Set-Content -LiteralPath (Join-Path $Root "ovms\$name") -Value "fixture-$RuntimeProfile-$name" -Encoding ASCII
    }
    Set-Content -LiteralPath (Join-Path $Root 'ovms\python\python.exe') -Value 'fixture-python' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Root 'ovms\tools\optimum\optimum-cli.cmd') -Value 'fixture-optimum-cli' -Encoding ASCII
    Write-HashManifest $Root

    $sourceSha = '0123456789abcdef0123456789abcdef01234567'
    if ($RuntimeProfile -eq 'maintainer-rc2') {
        $pins = [ordered]@{
            OV_SOURCE_BRANCH = '227c33757d1ef95d4da506d00686f923fdd2a535'
            OV_TOKENIZERS_BRANCH = 'a04accf6282d9b304214b492694b18c3979f667a'
            OV_GENAI_BRANCH = '7ea2546852a382cd16bd22dea0cfad2db70ed744'
            GENAI_PACKAGE_URL_WINDOWS = 'https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/pre-release/2026.4.0.0rc2/openvino_genai_windows_2026.4.0.0rc2_x86_64.zip'
        }
    } elseif ($RuntimeProfile -eq 'known-good-rc1') {
        $pins = [ordered]@{
            OV_SOURCE_BRANCH = '61afcb26271140347709138b13d678e8b1b5925c'
            OV_TOKENIZERS_BRANCH = 'a04accf6282d9b304214b492694b18c3979f667a'
            OV_GENAI_BRANCH = '5f7f1278107d7eae3990ce906bbcfcb69ac3397f'
            GENAI_PACKAGE_URL_WINDOWS = 'https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/pre-release/2026.4.0.0rc1/openvino_genai_windows_2026.4.0.0rc1_x86_64.zip'
        }
    } else {
        throw "Unsupported fixture runtime profile: $RuntimeProfile"
    }

    @(
        "OpenVINO backend 2026.4.0-00000-$($pins.OV_SOURCE_BRANCH.Substring(0, 11))",
        "OpenVINO GenAI backend 2026.4.0.0-0000-$($pins.OV_GENAI_BRANCH.Substring(0, 11))"
    ) | Set-Content -LiteralPath (Join-Path $Root 'provenance\ovms-version.txt') -Encoding UTF8

    $dllHashes = [ordered]@{}
    foreach ($name in @('openvino.dll','openvino_genai.dll','openvino_tokenizers.dll','tbb12.dll')) {
        $dllHashes[$name] = (Get-FileHash -LiteralPath (Join-Path $Root "ovms\$name") -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    [ordered]@{
        schema_version = 2
        project = 'GEMMAMONSTER'
        candidate_kind = 'stable-2026.4-refit'
        runtime_profile = $RuntimeProfile
        source_sha = $sourceSha
        repo_dirty = $false
        dependency_pins = $pins
        tooling = [ordered]@{
            python = '3.12.10'
            optimum = '2.3.0'
            optimum_intel = '2.1.0'
            openvino = '2026.3.1'
            openvino_tokenizers = '2026.3.1.0'
        }
        package = [ordered]@{
            ovms_sha256 = (Get-FileHash -LiteralPath (Join-Path $Root 'ovms\ovms.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
            dll_sha256 = $dllHashes
        }
        acceptance = [ordered]@{ status = 'NOT_RUN' }
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Root 'manifest.json') -Encoding UTF8

    return $sourceSha
}

function Expect-Failure([scriptblock]$Action, [string]$Contains) {
    $failure = $null
    try {
        & $Action
    } catch {
        $failure = $_
    }
    if ($null -eq $failure) {
        throw "Expected failure containing '$Contains', but action passed."
    }
    if ($failure.Exception.Message -notlike "*$Contains*") {
        throw "Expected failure containing '$Contains', got: $($failure.Exception.Message)"
    }
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("gemmamonster-contract-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try {
    foreach ($profile in @('maintainer-rc2','known-good-rc1')) {
        $candidate = Join-Path $temp $profile
        $sha = New-FakeCandidate -Root $candidate -RuntimeProfile $profile
        & $verifier -CandidateRoot $candidate -ExpectedSourceSha $sha -ExpectedRuntimeProfile $profile | Out-Null
    }

    $tampered = Join-Path $temp 'tampered'
    $sha = New-FakeCandidate -Root $tampered -RuntimeProfile 'maintainer-rc2'
    Add-Content -LiteralPath (Join-Path $tampered 'ovms\openvino.dll') -Value 'tamper' -Encoding ASCII
    Expect-Failure { & $verifier -CandidateRoot $tampered -ExpectedSourceSha $sha -ExpectedRuntimeProfile 'maintainer-rc2' | Out-Null } 'Hash mismatch'

    $wrongPin = Join-Path $temp 'wrong-pin'
    $sha = New-FakeCandidate -Root $wrongPin -RuntimeProfile 'maintainer-rc2'
    $manifestPath = Join-Path $wrongPin 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest.dependency_pins.OV_GENAI_BRANCH = '0000000000000000000000000000000000000000'
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Expect-Failure { & $verifier -CandidateRoot $wrongPin -ExpectedSourceSha $sha -ExpectedRuntimeProfile 'maintainer-rc2' | Out-Null } 'Dependency pin mismatch'

    $wrongVersion = Join-Path $temp 'wrong-version'
    $sha = New-FakeCandidate -Root $wrongVersion -RuntimeProfile 'maintainer-rc2'
    @(
        'OpenVINO backend 2026.4.0-00000-00000000000',
        'OpenVINO GenAI backend 2026.4.0.0-0000-00000000000'
    ) | Set-Content -LiteralPath (Join-Path $wrongVersion 'provenance\ovms-version.txt') -Encoding UTF8
    Expect-Failure { & $verifier -CandidateRoot $wrongVersion -ExpectedSourceSha $sha -ExpectedRuntimeProfile 'maintainer-rc2' | Out-Null } 'Runtime version fingerprint mismatch'

    $wrongSource = Join-Path $temp 'wrong-source'
    $sha = New-FakeCandidate -Root $wrongSource -RuntimeProfile 'known-good-rc1'
    Expect-Failure { & $verifier -CandidateRoot $wrongSource -ExpectedSourceSha 'ffffffffffffffffffffffffffffffffffffffff' -ExpectedRuntimeProfile 'known-good-rc1' | Out-Null } 'Source SHA mismatch'

    $missingDll = Join-Path $temp 'missing-dll'
    $sha = New-FakeCandidate -Root $missingDll -RuntimeProfile 'maintainer-rc2'
    Remove-Item -LiteralPath (Join-Path $missingDll 'ovms\openvino_tokenizers.dll') -Force
    Expect-Failure { & $verifier -CandidateRoot $missingDll -ExpectedSourceSha $sha -ExpectedRuntimeProfile 'maintainer-rc2' | Out-Null } 'Missing required runtime file'

    $missingTooling = Join-Path $temp 'missing-tooling'
    $sha = New-FakeCandidate -Root $missingTooling -RuntimeProfile 'maintainer-rc2'
    Remove-Item -LiteralPath (Join-Path $missingTooling 'ovms\tools\optimum\optimum-cli.cmd') -Force
    Write-HashManifest $missingTooling
    Expect-Failure { & $verifier -CandidateRoot $missingTooling -ExpectedSourceSha $sha -ExpectedRuntimeProfile 'maintainer-rc2' | Out-Null } 'Missing required tooling file'

    Write-Host 'GEMMAMONSTER_STABLE_CANDIDATE_CONTRACT_TEST_PASS'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
