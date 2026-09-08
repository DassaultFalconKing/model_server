$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$StartScript = Join-Path $RepoRoot "tools\gemmamonster-ovms\Start-GemmaMonsterOvms.ps1"
$StopScript = Join-Path $RepoRoot "tools\gemmamonster-ovms\Stop-GemmaMonsterOvms.ps1"
$ProbeScript = Join-Path $RepoRoot "tools\gemmamonster-ovms\Test-GemmaMonsterOvms.ps1"
$AcceptanceScript = Join-Path $RepoRoot "tools\gemmamonster-ovms\Test-GemmaMonsterAcceptance.ps1"
$ModelPath = "C:\llm\models\OpenVINO\Wondernutts\gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov"
$RuntimeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gemmamonster-ovms-test-" + [guid]::NewGuid().ToString("N"))

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message. Expected '$Expected', got '$Actual'."
    }
}

try {
    foreach ($Script in @($StartScript, $StopScript, $ProbeScript, $AcceptanceScript)) {
        if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) {
            throw "Required GEMMAMONSTER-OVMS script is missing: $Script"
        }
    }

    $Profiles = @{
        A = @{ Pipeline = "VLM"; PrefixCaching = $false }
        B = @{ Pipeline = "VLM_CB"; PrefixCaching = $false }
        C = @{ Pipeline = "VLM_CB"; PrefixCaching = $true }
        D = @{ Pipeline = "VLM_CB"; PrefixCaching = $false }
        E = @{ Pipeline = "VLM_CB"; PrefixCaching = $true }
    }
    foreach ($ProfileName in $Profiles.Keys) {
        $ProfileRuntime = Join-Path $RuntimeRoot $ProfileName
        $Result = & $StartScript `
            -ModelPath $ModelPath `
            -RuntimeRoot $ProfileRuntime `
            -RestPort 18888 `
            -GrpcPort 19888 `
            -Profile $ProfileName `
            -ValidateOnly

        Assert-Equal $Result.Status "VALID" "Validation status"
        Assert-Equal $Result.SourceContainsKnownGood $true "Known-good ancestry"
        Assert-Equal $Result.RestBaseUrl "http://127.0.0.1:18888/v3" "REST base URL"
        Assert-Equal $Result.QueueSize 0 "Graph queue size"
        Assert-Equal $Result.Pipeline $Profiles[$ProfileName].Pipeline "Pipeline for profile $ProfileName"
        Assert-Equal $Result.PrefixCaching $Profiles[$ProfileName].PrefixCaching "Prefix caching for profile $ProfileName"
        if ($ProfileName -eq "D") { Assert-Equal $Result.PerformanceHint "THROUGHPUT" "Performance hint for profile D" }

        $Config = Get-Content -LiteralPath $Result.ConfigPath -Raw | ConvertFrom-Json
        Assert-Equal $Config.mediapipe_config_list[0].name "gemma4" "Servable name"
        Assert-Equal $Config.mediapipe_config_list[0].graph_path ($Result.GraphPath -replace "\\", "/") "Graph path"

        $Graph = Get-Content -LiteralPath $Result.GraphPath -Raw
        if ($Graph -notmatch "pipeline_type:\s+$($Profiles[$ProfileName].Pipeline)") {
            throw "Generated graph has the wrong pipeline for profile $ProfileName."
        }
        if ($Graph -notmatch 'chat_template_mode:\s+MINJA') {
            throw "Generated graph does not select MINJA."
        }
        if ($Graph -notmatch 'max_num_seqs:\s+1') {
            throw "Generated graph does not isolate execution to one sequence."
        }
        if ($Graph -notmatch 'DYNAMIC_QUANTIZATION_GROUP_SIZE\\?"\s*:\s*\\?"0') {
            throw "Generated graph does not disable dynamic quantization."
        }
        if ($ProfileName -eq "E" -and $Graph -notmatch 'KV_CACHE_PRECISION\\?"\s*:\s*\\?"u8') {
            throw "Generated graph does not select u8 KV cache for profile E."
        }
        if ($Graph -notmatch [regex]::Escape(($ModelPath -replace "\\", "/"))) {
            throw "Generated graph does not contain the requested model path."
        }
    }

    $Plan = & $AcceptanceScript -PlanOnly
    Assert-Equal ($Plan.ContextTargets -join ",") "2000,4000,8000,12000,16000" "Persistent context targets"
    Assert-Equal ($Plan.StreamModes -join ",") "False,True" "Streaming matrix"
    Assert-Equal $Plan.ValidatesExactProbeArgument $true "Exact probe argument validation"
    Assert-Equal $Plan.ValidatesLongFreeText $true "Long free-text validation"
    Assert-Equal $Plan.ValidatesToolResultLoop $true "Tool-result loop validation"

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
