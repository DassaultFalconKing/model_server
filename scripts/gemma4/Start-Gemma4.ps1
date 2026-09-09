[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ModelPath,
    [string]$ModelName = 'gemma4-26-heretic',
    [int]$RestPort = 8000,
    [int]$GrpcPort = 9000,
    [int]$ReadinessTimeoutSeconds = 300,
    [switch]$Wait
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$gemmaRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$packageRoot = Split-Path -Parent $gemmaRoot
$ovms = Join-Path $packageRoot 'ovms.exe'
$profilePath = Join-Path $gemmaRoot 'profile-E\profile.json'
if (-not (Test-Path -LiteralPath $ovms -PathType Leaf)) { throw "ovms.exe not found: $ovms" }
$model = (Resolve-Path -LiteralPath $ModelPath).Path
$profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json

foreach ($port in @($RestPort, $GrpcPort)) {
    if (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) {
        throw "Port $port is already in use; refusing to kill an existing process."
    }
}

$runtimeRoot = Join-Path $env:LOCALAPPDATA 'OVMS\gemma4'
$runtimeDir = Join-Path $runtimeRoot ($ModelName + '-profile-e')
New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
$modelProto = $model.Replace('\', '/')
$runtimeProto = $runtimeDir.Replace('\', '/')
$pluginJson = ($profile.plugin_config | ConvertTo-Json -Compress)
$prefixLiteral = if ($profile.enable_prefix_caching) { 'true' } else { 'false' }

$graph = @"
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
  input_stream_info: { tag_index: "LOOPBACK:0" back_edge: true }
  node_options: {
    [type.googleapis.com / mediapipe.LLMCalculatorOptions]: {
      models_path: "$modelProto"
      device: "GPU"
      plugin_config: '$pluginJson'
      max_num_seqs: 1
      enable_prefix_caching: $prefixLiteral
      pipeline_type: VLM_CB
      chat_template_mode: JINJA
      max_tokens_limit: 65536
    }
  }
  input_stream_handler {
    input_stream_handler: "SyncSetInputStreamHandler"
    options { [mediapipe.SyncSetInputStreamHandlerOptions.ext] { sync_set { tag_index: "LOOPBACK:0" } } }
  }
}
"@
$graphPath = Join-Path $runtimeDir 'graph.pbtxt'
$graph | Set-Content -LiteralPath $graphPath -Encoding UTF8
$configPath = Join-Path $runtimeDir 'config.json'
[ordered]@{model_config_list=@();mediapipe_config_list=@([ordered]@{name=$ModelName;base_path=$runtimeProto})} |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $configPath -Encoding UTF8

$env:OVMS_GRAPH_QUEUE_MAX_SIZE = '0'
$env:PATH = "$packageRoot;$packageRoot\python;$packageRoot\python\Scripts;$env:PATH"
$pythonHome = Join-Path $packageRoot 'python'
if (Test-Path -LiteralPath (Join-Path $pythonHome 'python.exe')) {
    $env:PYTHONHOME = $pythonHome
    $env:PYTHONPATH = (Join-Path $pythonHome 'Lib\site-packages')
}

$logPath = Join-Path $runtimeDir 'ovms.log'
$arguments = @('--config_path',$configPath,'--rest_port',[string]$RestPort,'--port',[string]$GrpcPort,'--log_level','INFO','--log_path',$logPath)
$process = Start-Process -FilePath $ovms -ArgumentList $arguments -PassThru -WindowStyle Hidden
$deadline = [DateTime]::UtcNow.AddSeconds($ReadinessTimeoutSeconds)
do {
    if ($process.HasExited) { throw "OVMS exited with code $($process.ExitCode). Log: $logPath" }
    try {
        $ready = Invoke-WebRequest -Uri "http://127.0.0.1:$RestPort/v2/health/ready" -TimeoutSec 5 -UseBasicParsing
        if ($ready.StatusCode -eq 200) { break }
    } catch { }
    Start-Sleep -Seconds 2
} while ([DateTime]::UtcNow -lt $deadline)
if ([DateTime]::UtcNow -ge $deadline) { throw "OVMS readiness timed out. PID=$($process.Id), log=$logPath" }

Write-Host "OVMS READY pid=$($process.Id) model=$ModelName profile=E REST=http://127.0.0.1:$RestPort"
Write-Host "Runtime files: $runtimeDir"
if ($Wait) { Wait-Process -Id $process.Id; exit $process.ExitCode }
$process
