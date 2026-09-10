[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$verifier = Join-Path $root 'scripts\gemma4\Test-CandidateArtifact.ps1'
if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) {
    throw "Candidate artifact verifier is missing: $verifier"
}

function Write-Sha256Manifest {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [string[]]$ExcludeRelative = @()
    )

    $base = (Resolve-Path -LiteralPath $BasePath).Path
    $exclude = @($ExcludeRelative | ForEach-Object { $_.Replace('\\', '/').TrimStart('/') })
    $lines = foreach ($file in Get-ChildItem -LiteralPath $base -Recurse -File | Sort-Object FullName) {
        $relative = [System.IO.Path]::GetRelativePath($base, $file.FullName).Replace('\\', '/')
        if ($exclude -contains $relative) { continue }
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $relative"
    }
    $lines | Set-Content -LiteralPath $OutputPath -Encoding ascii
}

function New-SyntheticCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$GitSha
    )

    $ovms = Join-Path $Path 'ovms'
    $provenance = Join-Path $Path 'provenance'
    foreach ($dir in @($Path, $ovms, $provenance, (Join-Path $Path 'acceptance'), (Join-Path $Path 'logs'), (Join-Path $Path 'dumps'))) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    Set-Content -LiteralPath (Join-Path $ovms 'ovms.exe') -Value 'synthetic ovms payload' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $ovms 'openvino.dll') -Value 'synthetic openvino runtime' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $ovms 'openvino_genai.dll') -Value 'synthetic genai runtime' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $ovms 'openvino_tokenizers.dll') -Value 'synthetic tokenizers runtime' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $ovms 'tbb12.dll') -Value 'synthetic tbb runtime' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $ovms 'setupvars.bat') -Value '@echo off' -Encoding ascii

    Write-Sha256Manifest -BasePath $ovms -OutputPath (Join-Path $ovms 'SHA256SUMS') -ExcludeRelative @('SHA256SUMS')

    [ordered]@{
        schema_version = 1
        git_sha = $GitSha
        branch = 'synthetic/test'
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $provenance 'source.json') -Encoding UTF8

    [ordered]@{
        schema_version = 1
        bazel_target = '//src:ovms'
        bazel_config = 'win_mp_on_py_off'
        dependency_root = 'C:\\opt'
        openvino_dir = 'C:\\opt\\openvino\\runtime\\cmake'
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $provenance 'build.json') -Encoding UTF8

    [ordered]@{
        schema_version = 1
        entrypoint = 'ovms/ovms.exe'
        runtime_policy = 'SELF_CONTAINED_PACKAGE_ONLY'
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $provenance 'runtime.json') -Encoding UTF8

    $dependencyFiles = @('openvino.dll', 'openvino_genai.dll', 'openvino_tokenizers.dll', 'tbb12.dll')
    $dependencies = foreach ($name in $dependencyFiles) {
        $file = Join-Path $ovms $name
        [ordered]@{
            name = $name
            relative_path = "ovms/$name"
            sha256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    [ordered]@{
        schema_version = 1
        files = @($dependencies)
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $provenance 'dependencies.json') -Encoding UTF8

    $ovmsHash = (Get-FileHash -LiteralPath (Join-Path $ovms 'ovms.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
    [ordered]@{
        schema_version = 1
        contract = 'gemmamonster-candidate-v1'
        created_at_utc = [DateTime]::UtcNow.ToString('o')
        source = [ordered]@{
            git_sha = $GitSha
            branch = 'synthetic/test'
        }
        package = [ordered]@{
            root = 'ovms'
            entrypoint = 'ovms/ovms.exe'
            ovms_sha256 = $ovmsHash
        }
        evidence = [ordered]@{
            acceptance = 'acceptance'
            logs = 'logs'
            dumps = 'dumps'
        }
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Path 'manifest.json') -Encoding UTF8

    Write-Sha256Manifest -BasePath $Path -OutputPath (Join-Path $Path 'SHA256SUMS.txt') -ExcludeRelative @('SHA256SUMS.txt')
}

function Assert-ThrowsLike {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    try {
        & $Action
    } catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            throw "Expected error matching '$Pattern', got: $($_.Exception.Message)"
        }
        return
    }
    throw "Expected action to fail with pattern '$Pattern', but it succeeded."
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('gemmamonster-candidate-contract-' + [Guid]::NewGuid().ToString('N'))
$expectedSha = '0123456789abcdef0123456789abcdef01234567'

try {
    $valid = Join-Path $temp 'valid'
    New-SyntheticCandidate -Path $valid -GitSha $expectedSha

    $result = & $verifier -CandidateRoot $valid -ExpectedGitSha $expectedSha
    if ($result.Contract -ne 'gemmamonster-candidate-v1') { throw "Unexpected contract: $($result.Contract)" }
    if ($result.GitSha -ne $expectedSha) { throw "Unexpected git SHA: $($result.GitSha)" }
    if ($result.OvmsExe -ne (Join-Path $valid 'ovms\ovms.exe')) { throw "Unexpected entrypoint: $($result.OvmsExe)" }

    $missingManifest = Join-Path $temp 'missing-manifest'
    Copy-Item -LiteralPath $valid -Destination $missingManifest -Recurse
    Remove-Item -LiteralPath (Join-Path $missingManifest 'manifest.json') -Force
    Assert-ThrowsLike -Pattern 'manifest\.json' -Action {
        & $verifier -CandidateRoot $missingManifest -ExpectedGitSha $expectedSha | Out-Null
    }

    $tampered = Join-Path $temp 'tampered'
    Copy-Item -LiteralPath $valid -Destination $tampered -Recurse
    Add-Content -LiteralPath (Join-Path $tampered 'ovms\openvino.dll') -Value 'tamper'
    Assert-ThrowsLike -Pattern 'Hash mismatch|SHA256' -Action {
        & $verifier -CandidateRoot $tampered -ExpectedGitSha $expectedSha | Out-Null
    }

    Assert-ThrowsLike -Pattern 'git SHA mismatch' -Action {
        & $verifier -CandidateRoot $valid -ExpectedGitSha '89abcdef0123456789abcdef0123456789abcdef' | Out-Null
    }

    Write-Host 'GEMMAMONSTER_CANDIDATE_ARTIFACT_CONTRACT_TEST_PASS'
} finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Recurse -Force
    }
}
