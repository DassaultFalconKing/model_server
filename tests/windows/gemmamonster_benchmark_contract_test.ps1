[CmdletBinding()]
param([string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'))

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $RepoRoot 'scripts\gemmamonster\benchmark-running-model.ps1'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "Missing benchmark harness: $scriptPath" }
$source = Get-Content -LiteralPath $scriptPath -Raw

foreach ($required in @(
    '[double]$Temperature = 1.0', '[int]$TopK = 64', '[double]$TopP = 0.95',
    "@(1024, 2048)", "@(101, 102, 103)", "seed = (7000 + `$limit)", "seed = 777",
    "'curl'", "'InvokeWebRequest'", '/models', '/chat/completions',
    'completion_tokens', 'tokens_per_s', 'weighted_tokens_per_s', 'requests.ndjson', 'summary.csv'
)) {
    if (-not $source.Contains($required)) { throw "Missing benchmark contract fragment: $required" }
}

[void][scriptblock]::Create($source)

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
$listener.Stop()
$mock = Join-Path $PSScriptRoot 'gemmamonster_benchmark_mock_server.py'
$python = 'C:\opt\Python312\python.exe'
$process = Start-Process -FilePath $python -ArgumentList @($mock, $port) -PassThru -WindowStyle Hidden
$outputRoot = Join-Path ([IO.Path]::GetTempPath()) ("ovms-benchmark-contract-" + [guid]::NewGuid().ToString('N'))
try {
    for ($attempt = 0; $attempt -lt 40; ++$attempt) {
        try {
            Invoke-WebRequest -Uri "http://127.0.0.1:$port/v3/models" -TimeoutSec 1 | Out-Null
            break
        } catch {
            if ($attempt -eq 39) { throw }
            Start-Sleep -Milliseconds 100
        }
    }
    $runRoot = & $scriptPath -BaseUrl "http://127.0.0.1:$port/v3" -Model gemma-test -OutputRoot $outputRoot -TimeoutSec 10
    $rows = @(Get-Content -LiteralPath (Join-Path $runRoot 'requests.ndjson') | ForEach-Object { $_ | ConvertFrom-Json })
    if ($rows.Count -ne 14) { throw "Expected 14 benchmark rows, got $($rows.Count)" }
    if (@($rows.transport | Sort-Object -Unique) -join ',' -ne 'curl,InvokeWebRequest') { throw 'Both transports were not exercised' }
    if (@($rows | Where-Object { $_.response_model -ne 'gemma-test' -or $_.temperature -ne 1.0 -or $_.top_k -ne 64 -or $_.top_p -ne 0.95 }).Count) {
        throw 'Recorded model or sampling parameters differ from the request contract'
    }
    $aggregate = @(Get-Content -LiteralPath (Join-Path $runRoot 'aggregate.json') -Raw | ConvertFrom-Json)
    if ($aggregate.Count -ne 2 -or @($aggregate | Where-Object weighted_tokens_per_s -LE 0).Count) { throw 'Weighted throughput summary is invalid' }
} finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    if (Test-Path -LiteralPath $outputRoot) { Remove-Item -LiteralPath $outputRoot -Recurse -Force }
}
Write-Output 'GEMMAMONSTER_BENCHMARK_CONTRACT_TEST_PASS'
