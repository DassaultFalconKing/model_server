[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [string]$Label = 'gemma4-protocol-hardening',
    [string]$TokenizerPath = '',
    [switch]$BuildFirst,
    [string]$ShortRoot = 'g5'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$head = (& git -C $root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or -not $head) { throw 'Cannot resolve source HEAD.' }

if ($BuildFirst) {
    $builder = Join-Path $root 'scripts\gemma4\build-local-candidate.ps1'
    if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) { throw "Missing build helper: $builder" }
    & $builder -RepoRoot $root -ShortRoot $ShortRoot -Label $Label
    if ($LASTEXITCODE -ne 0) { throw "Build helper failed with exit code $LASTEXITCODE" }
}

if (-not $TokenizerPath) {
    $TokenizerPath = Join-Path $root 'src\test\llm_testing\OpenVINO\gemma-4-E4B-it-int4-ov'
}
if (-not (Test-Path -LiteralPath $TokenizerPath -PathType Container)) {
    throw "Gemma4 tokenizer directory not found: $TokenizerPath"
}
$env:GEMMA4_TOKENIZER_PATH = (Resolve-Path -LiteralPath $TokenizerPath).Path

$outDir = Join-Path $root ("tmp\gemmamonster-acceptance\" + $Label + "\protocol-tests-" + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$targets = @(
    [ordered]@{
        name = 'gemma4_parser_contract_test'
        relative = 'src\test\llm\gemma4_fast\gemma4_parser_contract_test.exe'
    },
    [ordered]@{
        name = 'gemma4_generation_contract_test'
        relative = 'src\test\llm\generation_config\gemma4_generation_contract_test.exe'
    },
    [ordered]@{
        name = 'gemma4_prompt_state_generation_contract_test'
        relative = 'src\test\llm\generation_config\gemma4_prompt_state_generation_contract_test.exe'
    },
    [ordered]@{
        name = 'gemma4_chat_template_overlay_contract_test'
        relative = 'src\test\llm\gemma4_overlay\gemma4_chat_template_overlay_contract_test.exe'
    },
    [ordered]@{
        name = 'gemma4_google_jinja_contract_test'
        relative = 'src\test\llm\gemma4_overlay\gemma4_google_jinja_contract_test.exe'
    },
    [ordered]@{
        name = 'openai_parallel_tool_calls_contract_test'
        relative = 'src\test\llm\generation_config\openai_parallel_tool_calls_contract_test.exe'
    }
)

function Resolve-TestExecutable([string]$Relative, [string]$Name) {
    $direct = Join-Path (Join-Path $root 'bazel-bin') $Relative
    if (Test-Path -LiteralPath $direct -PathType Leaf) {
        return (Resolve-Path -LiteralPath $direct).Path
    }

    $found = Get-ChildItem -LiteralPath $root -Filter ($Name + '.exe') -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'bazel-(bin|out)' } |
        Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

$results = @()
$failed = $false

foreach ($target in $targets) {
    $exe = Resolve-TestExecutable -Relative $target.relative -Name $target.name
    if (-not $exe) {
        $failed = $true
        $results += [ordered]@{
            name = $target.name
            status = 'MISSING'
            exit_code = $null
            executable = $null
            log = $null
        }
        continue
    }

    $log = Join-Path $outDir ($target.name + '.log')
    Write-Host "RUN $($target.name)"
    Write-Host "  exe: $exe"
    & $exe '--gtest_color=no' '--gtest_print_time=1' 2>&1 | Tee-Object -FilePath $log
    $code = $LASTEXITCODE
    $status = if ($code -eq 0) { 'PASS' } else { 'FAIL' }
    if ($code -ne 0) { $failed = $true }

    $results += [ordered]@{
        name = $target.name
        status = $status
        exit_code = $code
        executable = $exe
        executable_sha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
        log = $log
    }
}

$summary = [ordered]@{
    schema_version = 1
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
    git_head = $head
    repo_root = $root
    tokenizer_path = $env:GEMMA4_TOKENIZER_PATH
    overall = if ($failed) { 'FAIL' } else { 'PASS' }
    tests = $results
}
$summaryPath = Join-Path $outDir 'summary.json'
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host ''
Write-Host 'GEMMA4 PROTOCOL HARDENING TESTS'
Write-Host "  HEAD:    $head"
Write-Host "  overall: $($summary.overall)"
Write-Host "  summary: $summaryPath"

if ($failed) { exit 1 }
exit 0