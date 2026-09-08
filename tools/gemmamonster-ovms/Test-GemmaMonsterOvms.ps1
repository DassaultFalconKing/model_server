param(
    [string]$BaseUrl = "http://127.0.0.1:8888/v3",
    [string]$ModelName = "gemma4",
    [ValidateRange(1, 1000)][int]$Count = 1,
    [switch]$RequireToolCall
)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd("/")

$ModelsResponse = Invoke-RestMethod -Method Get -Uri "$BaseUrl/models" -TimeoutSec 10
if (-not $ModelsResponse) {
    throw "Empty response from $BaseUrl/models"
}

$Tools = @(
    [ordered]@{
        type = "function"
        function = [ordered]@{
            name = "question"
            description = "Return the requested question text"
            parameters = [ordered]@{
                type = "object"
                properties = [ordered]@{
                    text = [ordered]@{ type = "string" }
                }
                required = @("text")
                additionalProperties = $false
            }
        }
    }
)

$Failures = [System.Collections.Generic.List[object]]::new()
$Durations = [System.Collections.Generic.List[double]]::new()
for ($Index = 1; $Index -le $Count; $Index++) {
    $Payload = [ordered]@{
        model = $ModelName
        messages = @(
            [ordered]@{ role = "user"; content = "Call the question tool with text exactly probe-$Index" }
        )
        tools = $Tools
        tool_choice = [ordered]@{
            type = "function"
            function = [ordered]@{ name = "question" }
        }
        max_tokens = 128
        temperature = 0
    }

    $Started = Get-Date
    try {
        $Response = Invoke-RestMethod -Method Post -Uri "$BaseUrl/chat/completions" -ContentType "application/json" -Body ($Payload | ConvertTo-Json -Depth 20 -Compress) -TimeoutSec 180
        $Durations.Add(((Get-Date) - $Started).TotalSeconds)
        $ToolCall = $Response.choices[0].message.tool_calls[0]
        if ($RequireToolCall -and (-not $ToolCall -or $ToolCall.function.name -ne "question")) {
            throw "Expected question tool call was not returned."
        }
    }
    catch {
        $Failures.Add([pscustomobject]@{ Index = $Index; Error = $_.Exception.Message })
    }
}

$Result = [pscustomobject]@{
    BaseUrl = $BaseUrl
    Model = $ModelName
    Total = $Count
    Passed = $Count - $Failures.Count
    Failed = $Failures.Count
    AverageSeconds = if ($Durations.Count) { [math]::Round(($Durations | Measure-Object -Average).Average, 3) } else { $null }
    Failures = $Failures
}

$Result
if ($Failures.Count -gt 0) {
    throw "GEMMAMONSTER-OVMS probe failed: $($Failures.Count)/$Count requests failed."
}
