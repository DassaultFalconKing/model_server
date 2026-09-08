$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Templates = @(
    (Join-Path $RepoRoot "extras\chat_template_examples\chat_template_gemma.jinja"),
    (Join-Path $RepoRoot "src\test\llm\chat_templates\chat_template_gemma.jinja"),
    "C:\llm\models\OpenVINO\Wondernutts\gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov\chat_template.jinja"
)
foreach ($Template in $Templates) {
    $Text = Get-Content -LiteralPath $Template -Raw
    if ($Text -notmatch "GEMMA4_RECENT_TOOL_ATTRACTOR") {
        throw "Missing recent tool attractor in $Template"
    }
    if ($Text.LastIndexOf("GEMMA4_RECENT_TOOL_ATTRACTOR") -lt $Text.IndexOf("Loop through messages")) {
        throw "Tool attractor is not located after message history in $Template"
    }
}
Write-Host "PASS: Gemma4 recent tool attractor contract"
