param(
    [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$ModelPath = "C:\llm\models\OpenVINO\Wondernutts\gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov",
    [int]$ProbeCount = 3
)
$ErrorActionPreference = "Stop"
$Start = Join-Path $PSScriptRoot "Start-GemmaMonsterOvms.ps1"
$Stop = Join-Path $PSScriptRoot "Stop-GemmaMonsterOvms.ps1"
$Probe = Join-Path $PSScriptRoot "Test-GemmaMonsterOvms.ps1"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Root = Join-Path $RepoRoot "runtime\gemmamonster-optimization\$Stamp"
$Candidates = @(@{Name="B";Port=8895}, @{Name="D";Port=8896})
$Results = @()
foreach ($Candidate in $Candidates) {
    $Runtime = Join-Path $Root $Candidate.Name
    try {
        & $Start -RepoRoot $RepoRoot -ModelPath $ModelPath -RuntimeRoot $Runtime -RestPort $Candidate.Port -GrpcPort ($Candidate.Port + 100) -Profile $Candidate.Name | Out-Null
        Start-Sleep -Seconds 20
        $ProbeResult = & $Probe -BaseUrl "http://127.0.0.1:$($Candidate.Port)/v3" -Count $ProbeCount -RequireToolCall
        $Results += [pscustomobject]@{ Profile=$Candidate.Name; Passed=$ProbeResult.Passed; Failed=$ProbeResult.Failed; AverageSeconds=$ProbeResult.AverageSeconds; Status="PASS" }
    } catch {
        $Results += [pscustomobject]@{ Profile=$Candidate.Name; Passed=0; Failed=$ProbeCount; AverageSeconds=$null; Status="FAIL"; Error=$_.Exception.Message }
    } finally {
        & $Stop -RuntimeRoot $Runtime -ErrorAction SilentlyContinue | Out-Null
    }
}
$Passing = @($Results | Where-Object { $_.Status -eq "PASS" -and $_.Failed -eq 0 -and $_.AverageSeconds -ne $null } | Sort-Object AverageSeconds)
$Best = if ($Passing.Count) { $Passing[0].Profile } else { "B" }
$Summary = [pscustomobject]@{ BestProfile=$Best; Results=$Results; RuntimeRoot=$Root }
$Summary | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Root "summary.json") -Encoding UTF8
$Summary
