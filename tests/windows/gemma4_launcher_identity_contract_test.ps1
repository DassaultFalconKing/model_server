[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$launchers = @(
    (Join-Path $root 'scripts\gemma4\Start-Gemma4.ps1'),
    (Join-Path $root 'scripts\gemma4\launch-gemma4-candidate.ps1')
)

foreach ($launcher in $launchers) {
    $text = Get-Content -LiteralPath $launcher -Raw -Encoding UTF8
    foreach ($required in @(
        "[Alias('ModelName')][string]`$ModelId = 'gemma4-26b'",
        "[string]`$ModelDisplayName = 'Gemma 4 26B Heretic (Wondernutts)'",
        "model_id = `$ModelId",
        "model_display_name = `$ModelDisplayName",
        'server_version = $serverVersion',
        '/v3/models',
        'Published model id mismatch'
    )) {
        if (-not $text.Contains($required)) {
            throw "Launcher identity contract missing '$required' in $launcher"
        }
    }
    if ($text.Contains("name = `$ModelName")) {
        throw "Legacy ModelName is still used as the published API id in $launcher"
    }
}

$benchmark = Get-Content -LiteralPath (Join-Path $root 'scripts\gemma4\benchmark-legacy-prompts.ps1') -Raw -Encoding UTF8
if (-not $benchmark.Contains("[string]`$Model = 'gemma4-26b'")) {
    throw 'Benchmark default model id does not match the launcher identity contract.'
}
$semantic = Get-Content -LiteralPath (Join-Path $root 'scripts\gemma4\semantic_ab.py') -Raw -Encoding UTF8
if (-not $semantic.Contains("default='gemma4-26b'")) {
    throw 'Semantic A/B default model id does not match the launcher identity contract.'
}

$manifestPath = Join-Path $root 'scripts\gemma4\forward-port-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($surface in @('parser', 'reasoning_parser', 'generation', 'chat_template', 'runtime_identity')) {
    if (-not $manifest.future_upgrade_surfaces.$surface) {
        throw "Future upgrade surface is not documented: $surface"
    }
}

Write-Host 'GEMMA4_LAUNCHER_IDENTITY_CONTRACT_TEST_PASS'
