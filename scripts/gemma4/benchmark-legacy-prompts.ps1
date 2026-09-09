[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8000/v3',
    [string]$Model = 'gemma4-26-heretic',
    [int]$TimeoutSec = 1200
)

$ErrorActionPreference = 'Stop'
$uri = "$BaseUrl/chat/completions"

# These are the literal prompts and generation settings used by the frozen
# 2026.4 OVMS comparison. Keep this file as the reproducible benchmark source.
$longPrompt = 'Write a detailed continuous technical discussion of local large-language-model inference, memory bandwidth, KV caching, batching, and latency. Do not use tools, headings, bullet lists, or conclude early. Keep expanding naturally until the {0} token output limit.'
$shortPrompt = 'Generate a continuous technical explanation of transformer inference performance. Do not use tools, headings, lists, or an early conclusion. Continue until the token limit.'
$gpuPrompt = 'Write a continuous detailed technical explanation of GPU transformer inference optimization. Do not use tools, headings, lists, or a conclusion. Keep expanding the explanation until the token limit.'

function Invoke-BenchmarkRequest([hashtable]$Request) {
    $apiRequest = @{} + $Request
    $case = $apiRequest.case
    $apiRequest.Remove('case')
    $body = $apiRequest | ConvertTo-Json -Depth 12 -Compress
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Method Post -Uri $script:uri -ContentType 'application/json' -Body $body -TimeoutSec $script:TimeoutSec
    $sw.Stop()
    $tokens = [int]$response.usage.completion_tokens
    [pscustomobject]@{
        case = $case
        limit = [int]$Request.max_tokens
        seed = [int]$Request.seed
        elapsed_s = [math]::Round($sw.Elapsed.TotalSeconds, 3)
        prompt_tokens = [int]$response.usage.prompt_tokens
        completion_tokens = $tokens
        tokens_per_s = [math]::Round($tokens / $sw.Elapsed.TotalSeconds, 3)
        finish_reason = $response.choices[0].finish_reason
    }
}

$results = [System.Collections.Generic.List[object]]::new()
$warmup = @{ model = $Model; messages = @(@{ role = 'user'; content = 'Reply with a short sentence confirming readiness.' }); max_tokens = 16; temperature = 0; seed = 1; case = 'warmup' }
$results.Add((Invoke-BenchmarkRequest $warmup))

foreach ($limit in @(1024, 2048)) {
    $request = @{ model = $Model; messages = @(@{ role = 'user'; content = ($longPrompt -f $limit) }); max_tokens = $limit; temperature = 0.7; seed = (7000 + $limit); case = "long-$limit" }
    $results.Add((Invoke-BenchmarkRequest $request))
}

foreach ($seed in @(101, 102, 103)) {
    $request = @{ model = $Model; messages = @(@{ role = 'user'; content = $shortPrompt }); max_tokens = 128; temperature = 0.7; seed = $seed; case = "short-128-$seed" }
    $results.Add((Invoke-BenchmarkRequest $request))
}

$request = @{ model = $Model; messages = @(@{ role = 'user'; content = $gpuPrompt }); max_tokens = 512; temperature = 0.7; seed = 777; case = 'gpu-512' }
$results.Add((Invoke-BenchmarkRequest $request))

$results | ConvertTo-Json -Depth 8
