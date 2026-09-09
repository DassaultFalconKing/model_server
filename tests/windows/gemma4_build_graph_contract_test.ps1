$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$BuildFile = Join-Path $RepoRoot "src\BUILD"
$BuildText = Get-Content -LiteralPath $BuildFile -Raw
$PlatformUtilsTarget = [regex]::Match(
    $BuildText,
    '(?ms)cc_library\(\s*name\s*=\s*"test_platform_utils",.*?^\)'
)
if (-not $PlatformUtilsTarget.Success) {
    throw "Could not locate test_platform_utils in src/BUILD."
}

$VisibilityDeclarations = [regex]::Matches(
    $PlatformUtilsTarget.Value,
    '(?m)^\s*visibility\s*='
).Count
if ($VisibilityDeclarations -ne 1) {
    throw "test_platform_utils must have exactly one visibility declaration; found $VisibilityDeclarations."
}

$RequiredConsumers = @(
    "//src/test/llm/gemma4_fast:__pkg__",
    "//src/test/llm/generation_config:__pkg__"
)
foreach ($Consumer in $RequiredConsumers) {
    if (-not $PlatformUtilsTarget.Value.Contains($Consumer)) {
        throw "test_platform_utils visibility is missing required consumer: $Consumer"
    }
}

Write-Host "PASS: Gemma4 BUILD visibility contract"
