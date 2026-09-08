param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$ModelPath = "C:\llm\models\OpenVINO\Wondernutts\gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov",
    [string]$RuntimeRoot = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "runtime\gemmamonster-ovms"),
    [string]$ModelName = "gemma4",
    [int]$RestPort = 8888,
    [int]$GrpcPort = 9000,
    [ValidateSet("A", "B", "C", "D")][string]$Profile = "B",
    [ValidateRange(0, 1024)][int]$QueueSize = 0,
    [ValidateRange(1, 1048576)][int]$MaxTokensLimit = 65536,
    [switch]$Foreground,
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"
$KnownGoodCommit = "fea1a5f1c2640aa60fe6a840d3f62b38fb7b7767"
$RepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
$ModelPath = [System.IO.Path]::GetFullPath($ModelPath)
$RuntimeRoot = [System.IO.Path]::GetFullPath($RuntimeRoot)
$OvmsPath = Join-Path $RepoRoot "bazel-bin\src\ovms.exe"
$GraphPath = Join-Path $RuntimeRoot "graph.pbtxt"
$ConfigPath = Join-Path $RuntimeRoot "config.json"
$PidPath = Join-Path $RuntimeRoot "ovms.pid"
$OutLog = Join-Path $RuntimeRoot "ovms.stdout.log"
$ErrLog = Join-Path $RuntimeRoot "ovms.stderr.log"
$Pipeline = if ($Profile -eq "A") { "VLM" } else { "VLM_CB" }
$PrefixCaching = ($Profile -eq "C")
$PerformanceHint = if ($Profile -eq "D") { "THROUGHPUT" } else { "LATENCY" }
$PrefixCachingText = $PrefixCaching.ToString().ToLowerInvariant()

if ($ModelName -notmatch '^[A-Za-z0-9._-]+$') {
    throw "ModelName contains unsupported characters: $ModelName"
}
if ($RestPort -lt 1 -or $RestPort -gt 65535 -or $GrpcPort -lt 1 -or $GrpcPort -gt 65535) {
    throw "REST and gRPC ports must be in the range 1..65535."
}
if ($RestPort -eq $GrpcPort) {
    throw "REST and gRPC ports must be different."
}
if (-not (Test-Path -LiteralPath $OvmsPath -PathType Leaf)) {
    throw "Built GEMMAMONSTER-OVMS executable not found: $OvmsPath"
}
foreach ($RequiredModelFile in @("config.json", "openvino_language_model.xml", "openvino_tokenizer.xml")) {
    $RequiredPath = Join-Path $ModelPath $RequiredModelFile
    if (-not (Test-Path -LiteralPath $RequiredPath -PathType Leaf)) {
        throw "Required model file not found: $RequiredPath"
    }
}

$Head = (& git -C $RepoRoot rev-parse HEAD 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or -not $Head) {
    throw "Cannot resolve source HEAD under $RepoRoot"
}
& git -C $RepoRoot merge-base --is-ancestor $KnownGoodCommit $Head 2>$null
$SourceContainsKnownGood = ($LASTEXITCODE -eq 0)
if (-not $SourceContainsKnownGood) {
    throw "Source HEAD $Head does not contain known-good commit $KnownGoodCommit"
}

New-Item -ItemType Directory -Force -Path $RuntimeRoot | Out-Null
$ModelPathForGraph = $ModelPath.Replace("\", "/")
$GraphPathForConfig = $GraphPath.Replace("\", "/")

$Graph = @"
# GEMMAMONSTER-OVMS diagnostic profile $Profile.
# Source baseline: $KnownGoodCommit
# OVMS_GRAPH_QUEUE_MAX_SIZE: $QueueSize
input_stream: "HTTP_REQUEST_PAYLOAD:input"
output_stream: "HTTP_RESPONSE_PAYLOAD:output"

node: {
  name: "LLMExecutor"
  calculator: "HttpLLMCalculator"
  input_stream: "LOOPBACK:loopback"
  input_stream: "HTTP_REQUEST_PAYLOAD:input"
  input_side_packet: "LLM_NODE_RESOURCES:llm"
  input_side_packet: "LLM_NODE_EXECUTION_CONTEXTS:llm_ctx"
  output_stream: "LOOPBACK:loopback"
  output_stream: "HTTP_RESPONSE_PAYLOAD:output"
  input_stream_info: {
    tag_index: "LOOPBACK:0"
    back_edge: true
  }
  node_options: {
    [type.googleapis.com / mediapipe.LLMCalculatorOptions]: {
      models_path: "$ModelPathForGraph"
      device: "GPU"
      plugin_config: '{"DYNAMIC_QUANTIZATION_GROUP_SIZE":"0","PERFORMANCE_HINT":"$PerformanceHint"}'
      max_num_seqs: 1
      enable_prefix_caching: $PrefixCachingText
      cache_size: 0
      pipeline_type: $Pipeline
      chat_template_mode: MINJA
      tool_parser: gemma4
      reasoning_parser: gemma4
      enable_tool_guided_generation: true
      max_tokens_limit: $MaxTokensLimit
    }
  }
  input_stream_handler {
    input_stream_handler: "SyncSetInputStreamHandler"
    options {
      [mediapipe.SyncSetInputStreamHandlerOptions.ext] {
        sync_set { tag_index: "LOOPBACK:0" }
      }
    }
  }
}
"@

$Config = [ordered]@{
    model_config_list = @()
    mediapipe_config_list = @(
        [ordered]@{
            name = $ModelName
            graph_path = $GraphPathForConfig
        }
    )
}

$Graph | Set-Content -LiteralPath $GraphPath -Encoding utf8NoBOM
$Config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ConfigPath -Encoding utf8NoBOM

$Result = [pscustomobject]@{
    Status = if ($ValidateOnly) { "VALID" } else { "STARTING" }
    SourceHead = $Head
    KnownGoodCommit = $KnownGoodCommit
    SourceContainsKnownGood = $SourceContainsKnownGood
    OvmsPath = $OvmsPath
    ModelPath = $ModelPath
    ModelName = $ModelName
    Profile = $Profile
    Pipeline = $Pipeline
    PrefixCaching = $PrefixCaching
    PerformanceHint = $PerformanceHint
    QueueSize = $QueueSize
    RestBaseUrl = "http://127.0.0.1:$RestPort/v3"
    GrpcPort = $GrpcPort
    RuntimeRoot = $RuntimeRoot
    GraphPath = $GraphPath
    ConfigPath = $ConfigPath
    PidPath = $PidPath
    StdoutLog = $OutLog
    StderrLog = $ErrLog
}

if ($ValidateOnly) {
    return $Result
}

foreach ($Port in @($RestPort, $GrpcPort)) {
    if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) {
        throw "Port $Port is already in use."
    }
}
if (Test-Path -LiteralPath $PidPath) {
    throw "PID file already exists: $PidPath. Run Stop-GemmaMonsterOvms.ps1 first or inspect it manually."
}

Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
$env:GEMMA4_TOKENIZER_PATH = $ModelPath
$env:OVMS_GRAPH_QUEUE_MAX_SIZE = "$QueueSize"
$env:PATH = "$(Split-Path -Parent $OvmsPath);$RepoRoot;$env:PATH"
$Arguments = @("--rest_port", "$RestPort", "--port", "$GrpcPort", "--config_path", $ConfigPath)

Write-Host "GEMMAMONSTER-OVMS source: $Head"
Write-Host "Known-good baseline:       $KnownGoodCommit"
Write-Host "Diagnostic profile:        $Profile"
Write-Host "Pipeline:                  $Pipeline (queue=$QueueSize, prefix_caching=$PrefixCachingText, hint=$PerformanceHint)"
Write-Host "OpenAI base URL:           http://127.0.0.1:$RestPort/v3"
Write-Host "Model:                     $ModelPath"

if ($Foreground) {
    & $OvmsPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "GEMMAMONSTER-OVMS exited with code $LASTEXITCODE"
    }
    return
}

Remove-Item -LiteralPath $OutLog, $ErrLog -ErrorAction SilentlyContinue
$Process = Start-Process -FilePath $OvmsPath -ArgumentList $Arguments -WorkingDirectory $RepoRoot -WindowStyle Hidden -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog -PassThru
$Process.Id | Set-Content -LiteralPath $PidPath -Encoding ascii -NoNewline
$Result.Status = "STARTED"
$Result | Add-Member -NotePropertyName ProcessId -NotePropertyValue $Process.Id
return $Result
