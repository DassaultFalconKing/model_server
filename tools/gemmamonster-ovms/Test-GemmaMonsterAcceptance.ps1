param(
    [string]$BaseUrl = "http://127.0.0.1:8888/v3",
    [string]$ModelName = "gemma4",
    [int[]]$ContextTargets = @(2000, 4000, 8000, 12000, 16000),
    [ValidateRange(300, 500)][int]$LongMaxTokens = 450,
    [string]$OutputRoot = (Join-Path (Get-Location) "runtime\gemmamonster-acceptance"),
    [switch]$PlanOnly
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$BaseUrl = $BaseUrl.TrimEnd("/")
$Plan = [pscustomobject]@{
    ContextTargets = $ContextTargets
    StreamModes = @($false, $true)
    ValidatesExactProbeArgument = $true
    ValidatesLongFreeText = $true
    ValidatesToolResultLoop = $true
}
if ($PlanOnly) {
    return $Plan
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$RunRoot = Join-Path $OutputRoot $RunId
New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

function ConvertTo-JsonBody {
    param([Parameter(Mandatory)]$Value)
    return ($Value | ConvertTo-Json -Depth 30 -Compress)
}

function Invoke-Chat {
    param(
        [Parameter(Mandatory)]$Payload,
        [Parameter(Mandatory)][string]$EvidenceName
    )

    $EvidencePath = Join-Path $RunRoot "$EvidenceName.json"
    $Started = Get-Date
    if (-not $Payload.stream) {
        $Response = Invoke-RestMethod -Method Post -Uri "$BaseUrl/chat/completions" -ContentType "application/json" -Body (ConvertTo-JsonBody $Payload) -TimeoutSec 300
        $Response | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $EvidencePath -Encoding utf8NoBOM
        return [pscustomobject]@{
            Raw = $Response
            Message = $Response.choices[0].message
            FinishReason = $Response.choices[0].finish_reason
            Usage = $Response.usage
            ElapsedSeconds = ((Get-Date) - $Started).TotalSeconds
            EvidencePath = $EvidencePath
        }
    }

    $WebResponse = Invoke-WebRequest -Method Post -Uri "$BaseUrl/chat/completions" -ContentType "application/json" -Body (ConvertTo-JsonBody $Payload) -TimeoutSec 300 -UseBasicParsing
    $WebResponse.Content | Set-Content -LiteralPath ($EvidencePath -replace '\.json$', '.sse.txt') -Encoding utf8NoBOM
    $ContentBuilder = [System.Text.StringBuilder]::new()
    $ToolName = ""
    $ToolId = ""
    $ArgumentsBuilder = [System.Text.StringBuilder]::new()
    $FinishReason = ""
    $Usage = $null
    foreach ($Line in ($WebResponse.Content -split "`r?`n")) {
        if ($Line -notmatch '^data:\s*(.+)$' -or $Matches[1] -eq '[DONE]') { continue }
        $Chunk = $Matches[1] | ConvertFrom-Json
        if ($Chunk.usage) { $Usage = $Chunk.usage }
        if (-not $Chunk.choices -or $Chunk.choices.Count -eq 0) { continue }
        $Choice = $Chunk.choices[0]
        if ($Choice.finish_reason) { $FinishReason = $Choice.finish_reason }
        $Delta = $Choice.delta
        if ($null -ne $Delta.content) { [void]$ContentBuilder.Append([string]$Delta.content) }
        if ($Delta.tool_calls) {
            $Part = $Delta.tool_calls[0]
            if ($Part.id) { $ToolId = $Part.id }
            if ($Part.function.name) { $ToolName += [string]$Part.function.name }
            if ($null -ne $Part.function.arguments) { [void]$ArgumentsBuilder.Append([string]$Part.function.arguments) }
        }
    }
    $Message = [pscustomobject]@{
        role = "assistant"
        content = $ContentBuilder.ToString()
        tool_calls = if ($ToolName) { @([pscustomobject]@{ id = $ToolId; type = "function"; function = [pscustomobject]@{ name = $ToolName; arguments = $ArgumentsBuilder.ToString() } }) } else { @() }
    }
    $Normalized = [pscustomobject]@{ message = $Message; finish_reason = $FinishReason; usage = $Usage }
    $Normalized | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $EvidencePath -Encoding utf8NoBOM
    return [pscustomobject]@{
        Raw = $Normalized
        Message = $Message
        FinishReason = $FinishReason
        Usage = $Usage
        ElapsedSeconds = ((Get-Date) - $Started).TotalSeconds
        EvidencePath = $EvidencePath
    }
}

function Test-TextQuality {
    param([string]$Content, $Usage)
    $Words = @([regex]::Matches($Content, "[A-Za-z]{2,}") | ForEach-Object { $_.Value.ToLowerInvariant() })
    $UniqueRatio = if ($Words.Count) { (@($Words | Sort-Object -Unique).Count / $Words.Count) } else { 0 }
    $LongestToken = if ($Words.Count) { ($Words | Sort-Object Length -Descending | Select-Object -First 1).Length } else { 0 }
    $CompletionTokens = if ($Usage -and $null -ne $Usage.completion_tokens) { [int]$Usage.completion_tokens } else { 0 }
    $Reasons = [System.Collections.Generic.List[string]]::new()
    if ($CompletionTokens -lt 300) { $Reasons.Add("completion_tokens_below_300") }
    if ($Content.Length -lt 900) { $Reasons.Add("content_too_short") }
    if ($UniqueRatio -lt 0.12) { $Reasons.Add("low_lexical_diversity") }
    if ($LongestToken -gt 45) { $Reasons.Add("suspicious_long_morpheme") }
    if ($Content -match '(?i)(\b\w{1,3}\b[ ,]*){18,}') { $Reasons.Add("morpheme_soup_pattern") }
    return [pscustomobject]@{
        Clean = ($Reasons.Count -eq 0)
        Reasons = @($Reasons)
        CompletionTokens = $CompletionTokens
        CharacterCount = $Content.Length
        WordCount = $Words.Count
        UniqueWordRatio = [math]::Round($UniqueRatio, 3)
        LongestAlphabeticToken = $LongestToken
    }
}

$QuestionTool = [ordered]@{
    type = "function"
    function = [ordered]@{
        name = "question"
        description = "Echo a diagnostic probe string"
        parameters = [ordered]@{
            type = "object"
            properties = [ordered]@{ text = [ordered]@{ type = "string" } }
            required = @("text")
            additionalProperties = $false
        }
    }
}
$CalculateTool = [ordered]@{
    type = "function"
    function = [ordered]@{
        name = "calculate"
        description = "Calculate an arithmetic expression"
        parameters = [ordered]@{
            type = "object"
            properties = [ordered]@{ expression = [ordered]@{ type = "string" } }
            required = @("expression")
            additionalProperties = $false
        }
    }
}

$Results = [System.Collections.Generic.List[object]]::new()
foreach ($Stream in @($false, $true)) {
    $Mode = if ($Stream) { "stream" } else { "unary" }
    $ProbeValue = "probe-$RunId-$Mode"
    $ProbePayload = [ordered]@{
        model = $ModelName
        messages = @([ordered]@{ role = "user"; content = "Call question with text exactly $ProbeValue" })
        tools = @($QuestionTool)
        tool_choice = [ordered]@{ type = "function"; function = [ordered]@{ name = "question" } }
        stream = $Stream
        temperature = 0
        max_tokens = 128
    }
    if ($Stream) { $ProbePayload.stream_options = [ordered]@{ include_usage = $true } }
    $Probe = Invoke-Chat -Payload $ProbePayload -EvidenceName "$Mode-exact-probe"
    $ProbeTool = $Probe.Message.tool_calls[0]
    $ProbeArguments = try { $ProbeTool.function.arguments | ConvertFrom-Json } catch { $null }
    $ProbePass = ($ProbeTool.function.name -eq "question" -and $ProbeArguments.text -ceq $ProbeValue)
    $Results.Add([pscustomobject]@{ Test = "exact_probe"; Mode = $Mode; TargetTokens = $null; PromptTokens = $Probe.Usage.prompt_tokens; Pass = $ProbePass; Detail = $ProbeTool.function.arguments; Evidence = $Probe.EvidencePath })

    $LoopMessages = @([ordered]@{ role = "user"; content = "Use calculate to compute 17 * 23. Then, after receiving the tool result, answer with exactly RESULT=391." })
    $LoopRequest = [ordered]@{ model = $ModelName; messages = $LoopMessages; tools = @($CalculateTool); tool_choice = "auto"; stream = $Stream; temperature = 0; max_tokens = 128 }
    if ($Stream) { $LoopRequest.stream_options = [ordered]@{ include_usage = $true } }
    $LoopFirst = Invoke-Chat -Payload $LoopRequest -EvidenceName "$Mode-loop-tool-call"
    $Call = $LoopFirst.Message.tool_calls[0]
    $CallArgs = try { $Call.function.arguments | ConvertFrom-Json } catch { $null }
    $CallValid = ($Call.function.name -eq "calculate" -and $CallArgs.expression -match '17\s*\*\s*23')
    if ($CallValid) {
        $LoopMessages += [ordered]@{ role = "assistant"; content = $LoopFirst.Message.content; tool_calls = @([ordered]@{ id = $Call.id; type = "function"; function = [ordered]@{ name = $Call.function.name; arguments = $Call.function.arguments } }) }
        $LoopMessages += [ordered]@{ role = "tool"; tool_call_id = $Call.id; name = "calculate"; content = '{"result":391}' }
        $LoopRequest.messages = $LoopMessages
        $LoopRequest.tool_choice = "auto"
        $LoopFinal = Invoke-Chat -Payload $LoopRequest -EvidenceName "$Mode-loop-final"
        $LoopPass = ($LoopFinal.Message.content -match 'RESULT\s*=\s*391')
        $Results.Add([pscustomobject]@{ Test = "tool_result_loop"; Mode = $Mode; TargetTokens = $null; PromptTokens = $LoopFinal.Usage.prompt_tokens; Pass = $LoopPass; Detail = $LoopFinal.Message.content; Evidence = $LoopFinal.EvidencePath })
    }
    else {
        $Results.Add([pscustomobject]@{ Test = "tool_result_loop"; Mode = $Mode; TargetTokens = $null; PromptTokens = $LoopFirst.Usage.prompt_tokens; Pass = $false; Detail = "Invalid calculate call: $($Call.function.arguments)"; Evidence = $LoopFirst.EvidencePath })
    }

    $History = @([ordered]@{ role = "system"; content = "Write coherent English prose. Never call tools. Preserve the checkpoint label requested by the user." })
    $PreviousPromptTokens = 0
    foreach ($Target in $ContextTargets) {
        $NeededTokens = [math]::Max(500, $Target - $PreviousPromptTokens - 180)
        # Each generated archive phrase consumes about seven Gemma tokens.
        # Actual prompt_tokens are recorded and drive the next persistent step.
        $FillerCount = [math]::Ceiling($NeededTokens / 7)
        $Filler = [string]::Join(' ', (1..$FillerCount | ForEach-Object { "archive$($_ % 97) records stable context evidence" }))
        $Checkpoint = "CHECKPOINT-$Target-$Mode"
        $History += [ordered]@{ role = "user"; content = "$Filler`nWrite a coherent technical essay of at least 320 tokens and at most 430 tokens about reliable software testing. Begin with $Checkpoint and end with END-$Checkpoint. Do not use tools." }
        $LongRequest = [ordered]@{ model = $ModelName; messages = $History; stream = $Stream; temperature = 0; max_tokens = $LongMaxTokens }
        if ($Stream) { $LongRequest.stream_options = [ordered]@{ include_usage = $true } }
        $LongResponse = Invoke-Chat -Payload $LongRequest -EvidenceName "$Mode-context-$Target"
        $Quality = Test-TextQuality -Content ([string]$LongResponse.Message.content) -Usage $LongResponse.Usage
        $HasStartAnchor = ($LongResponse.Message.content -match [regex]::Escape($Checkpoint))
        $HasEndAnchor = ($LongResponse.Message.content -match [regex]::Escape("END-$Checkpoint"))
        $Pass = ($Quality.Clean -and $HasStartAnchor)
        $Results.Add([pscustomobject]@{ Test = "persistent_long_text"; Mode = $Mode; TargetTokens = $Target; PromptTokens = $LongResponse.Usage.prompt_tokens; Pass = $Pass; Detail = [pscustomobject]@{ Quality = $Quality; HasStartAnchor = $HasStartAnchor; HasEndAnchor = $HasEndAnchor; FinishReason = $LongResponse.FinishReason }; Evidence = $LongResponse.EvidencePath })
        $PreviousPromptTokens = [int]$LongResponse.Usage.prompt_tokens
        $History += [ordered]@{ role = "assistant"; content = $LongResponse.Message.content }
    }
}

$Summary = [pscustomobject]@{
    RunId = $RunId
    BaseUrl = $BaseUrl
    Model = $ModelName
    Passed = @($Results | Where-Object Pass).Count
    Failed = @($Results | Where-Object { -not $_.Pass }).Count
    Results = $Results
    EvidenceRoot = $RunRoot
}
$Summary | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $RunRoot "summary.json") -Encoding utf8NoBOM
$Summary
if ($Summary.Failed -gt 0) {
    throw "GEMMAMONSTER acceptance failed: $($Summary.Failed) checks failed. Evidence: $RunRoot"
}
