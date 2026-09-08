$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$StartScript = Join-Path $RepoRoot "tools\gemmamonster-ovms\Start-GemmaMonsterOvms.ps1"
$StopScript = Join-Path $RepoRoot "tools\gemmamonster-ovms\Stop-GemmaMonsterOvms.ps1"
$ProbeScript = Join-Path $RepoRoot "tools\gemmamonster-ovms\Test-GemmaMonsterOvms.ps1"
$ModelPath = "C:\llm\models\OpenVINO\Wondernutts\gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov"
$RuntimeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gemmamonster-ovms-test-" + [guid]::NewGuid().ToString("N"))

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message. Expected '$Expected', got '$Actual'."
    }
}

try {
    foreach ($Script in @($StartScript, $StopScript, $ProbeScript)) {
        if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) {
            throw "Required GEMMAMONSTER-OVMS script is missing: $Script"
        }
    }

    $Result = & $StartScript `
        -ModelPath $ModelPath `
        -RuntimeRoot $RuntimeRoot `
        -RestPort 18888 `
        -GrpcPort 19888 `
        -QueueSize 0 `
        -ValidateOnly

    Assert-Equal $Result.Status "VALID" "Validation status"
    Assert-Equal $Result.SourceContainsKnownGood $true "Known-good ancestry"
    Assert-Equal $Result.RestBaseUrl "http://127.0.0.1:18888/v3" "REST base URL"
    Assert-Equal $Result.QueueSize 0 "Graph queue size"

    $Config = Get-Content -LiteralPath $Result.ConfigPath -Raw | ConvertFrom-Json
    Assert-Equal $Config.mediapipe_config_list[0].name "gemma4" "Servable name"
    Assert-Equal $Config.mediapipe_config_list[0].graph_path ($Result.GraphPath -replace "\\", "/") "Graph path"

    $Graph = Get-Content -LiteralPath $Result.GraphPath -Raw
    if ($Graph -notmatch 'pipeline_type:\s+VLM_CB') {
        throw "Generated graph does not select pipeline_type VLM_CB."
    }
    if ($Graph -notmatch 'chat_template_mode:\s+MINJA') {
        throw "Generated graph does not select MINJA."
    }
    if ($Graph -notmatch [regex]::Escape(($ModelPath -replace "\\", "/"))) {
        throw "Generated graph does not contain the requested model path."
    }

    & $StopScript -RuntimeRoot $RuntimeRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Stop script must succeed when no PID file exists."
    }

    Write-Host "PASS: GEMMAMONSTER-OVMS script contract"
}
finally {
    if (Test-Path -LiteralPath $RuntimeRoot) {
        Remove-Item -LiteralPath $RuntimeRoot -Recurse -Force
    }
}
