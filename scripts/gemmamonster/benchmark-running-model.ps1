[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8000/v3',
    [Parameter(Mandatory)][string]$Model,
    [string]$OutputRoot = 'C:\gemmamonster-artifacts\benchmarks',
    [int]$TimeoutSec = 1200,
    [double]$Temperature = 1.0,
    [int]$TopK = 64,
    [double]$TopP = 0.95
)

$ErrorActionPreference = 'Stop'
$base = $BaseUrl.TrimEnd('/')
$uri = "$base/chat/completions"
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$safeModel = $Model -replace '[^A-Za-z0-9._-]', '_'
$runRoot = Join-Path $OutputRoot "$stamp-$safeModel"
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$modelsResponse = Invoke-WebRequest -Method Get -Uri "$base/models" -TimeoutSec $TimeoutSec
$modelsResponse.Content | Set-Content -LiteralPath (Join-Path $runRoot 'models-response.json') -Encoding utf8NoBOM
$published = @((ConvertFrom-Json $modelsResponse.Content).data.id)
if ($published -notcontains $Model) { throw "Requested model '$Model' is not published by $base/models" }

$metadata = [ordered]@{
    timestamp_utc = $stamp
    endpoint = $base
    requested_model = $Model
    published_models = $published
    sampling = [ordered]@{ do_sample = $true; temperature = $Temperature; top_k = $TopK; top_p = $TopP }
    throughput = 'completion_tokens / client wall time seconds'
}
$metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'run.json') -Encoding utf8NoBOM

$cases = [Collections.Generic.List[object]]::new()
$cases.Add([ordered]@{ case = 'warmup'; max_tokens = 16; seed = 1; prompt = 'Reply with a short sentence confirming readiness.' })
$longPrompt = 'Write a detailed continuous technical discussion of local large-language-model inference, memory bandwidth, KV caching, batching, and latency. Do not use tools, headings, bullet lists, or conclude early. Keep expanding naturally until the {0} token output limit.'
foreach ($limit in @(1024, 2048)) {
    $cases.Add([ordered]@{ case = "long-$limit"; max_tokens = $limit; seed = (7000 + $limit); prompt = ($longPrompt -f $limit) })
}
$shortPrompt = 'Generate a continuous technical explanation of transformer inference performance. Do not use tools, headings, lists, or an early conclusion. Continue until the token limit.'
foreach ($seed in @(101, 102, 103)) {
    $cases.Add([ordered]@{ case = "short-128-$seed"; max_tokens = 128; seed = $seed; prompt = $shortPrompt })
}
$cases.Add([ordered]@{ case = 'gpu-512'; max_tokens = 512; seed = 777; prompt = 'Write a continuous detailed technical explanation of GPU transformer inference optimization. Do not use tools, headings, lists, or a conclusion. Keep expanding the explanation until the token limit.' })

$results = [Collections.Generic.List[object]]::new()
foreach ($case in $cases) {
    $payload = [ordered]@{
        model = $Model
        messages = @([ordered]@{ role = 'user'; content = $case.prompt })
        max_tokens = $case.max_tokens
        temperature = $Temperature
        top_k = $TopK
        top_p = $TopP
        seed = $case.seed
    }
    $body = $payload | ConvertTo-Json -Depth 12 -Compress
    foreach ($transport in @('curl', 'InvokeWebRequest')) {
        $stem = "$($case.case)-$transport"
        $requestPath = Join-Path $runRoot "$stem-request.json"
        $responsePath = Join-Path $runRoot "$stem-response.json"
        $body | Set-Content -LiteralPath $requestPath -Encoding utf8NoBOM
        $sw = [Diagnostics.Stopwatch]::StartNew()
        if ($transport -eq 'curl') {
            $statusText = & curl.exe --silent --show-error --output $responsePath --write-out '%{http_code}' --request POST --header 'Content-Type: application/json' --data-binary "@$requestPath" $uri
            $curlExit = $LASTEXITCODE
            $status = [int]$statusText
            if ($curlExit -ne 0) { throw "curl failed for $($case.case), exit $curlExit" }
            $raw = Get-Content -LiteralPath $responsePath -Raw
        } else {
            $web = Invoke-WebRequest -Method Post -Uri $uri -ContentType 'application/json' -Body $body -TimeoutSec $TimeoutSec -SkipHttpErrorCheck
            $status = [int]$web.StatusCode
            $raw = $web.Content
            $raw | Set-Content -LiteralPath $responsePath -Encoding utf8NoBOM
        }
        $sw.Stop()
        $response = $raw | ConvertFrom-Json
        $completionTokens = [int]$response.usage.completion_tokens
        $row = [ordered]@{
            timestamp_utc = [DateTime]::UtcNow.ToString('o')
            case = $case.case
            transport = $transport
            endpoint = $uri
            requested_model = $Model
            response_model = [string]$response.model
            max_tokens = [int]$case.max_tokens
            seed = [int]$case.seed
            do_sample = $true
            temperature = $Temperature
            top_k = $TopK
            top_p = $TopP
            http_status = $status
            elapsed_s = [math]::Round($sw.Elapsed.TotalSeconds, 3)
            prompt_tokens = [int]$response.usage.prompt_tokens
            completion_tokens = $completionTokens
            total_tokens = [int]$response.usage.total_tokens
            tokens_per_s = if ($sw.Elapsed.TotalSeconds -gt 0) { [math]::Round($completionTokens / $sw.Elapsed.TotalSeconds, 3) } else { 0 }
            finish_reason = [string]$response.choices[0].finish_reason
            request_path = $requestPath
            response_path = $responsePath
        }
        $results.Add([pscustomobject]$row)
        ($row | ConvertTo-Json -Depth 8 -Compress) | Add-Content -LiteralPath (Join-Path $runRoot 'requests.ndjson') -Encoding utf8NoBOM
        if ($status -lt 200 -or $status -ge 300) { throw "HTTP $status for $($case.case) via $transport" }
    }
}

$results | Export-Csv -LiteralPath (Join-Path $runRoot 'summary.csv') -NoTypeInformation -Encoding utf8NoBOM
$aggregate = foreach ($transport in @('curl', 'InvokeWebRequest')) {
    $long = @($results | Where-Object { $_.transport -eq $transport -and $_.case -like 'long-*' })
    $tokens = ($long | Measure-Object completion_tokens -Sum).Sum
    $seconds = ($long | Measure-Object elapsed_s -Sum).Sum
    [pscustomobject]@{
        transport = $transport
        cases = $long.Count
        completion_tokens = [int]$tokens
        elapsed_s = [math]::Round($seconds, 3)
        weighted_tokens_per_s = if ($seconds -gt 0) { [math]::Round($tokens / $seconds, 3) } else { 0 }
    }
}
$aggregate | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runRoot 'aggregate.json') -Encoding utf8NoBOM
Write-Output $runRoot
