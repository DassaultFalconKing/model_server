[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'forward-port-manifest.json'),
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$manifestFile = (Resolve-Path -LiteralPath $ManifestPath).Path
$manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
$results = New-Object System.Collections.Generic.List[object]

function Add-Result([string]$Status, [string]$Check, [string]$Detail) {
    $results.Add([ordered]@{ status = $Status; check = $Check; detail = $Detail })
    $prefix = if ($Status -eq 'PASS') { '[PASS]' } elseif ($Status -eq 'WARN') { '[WARN]' } else { '[FAIL]' }
    Write-Host "$prefix $Check :: $Detail"
}

function Get-Git([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args) {
    $text = (& git -C $root @Args 2>&1 | Out-String).Trim()
    return [ordered]@{ exit_code = $LASTEXITCODE; text = $text }
}

$head = Get-Git rev-parse HEAD
if ($head.exit_code -ne 0) { throw "Cannot resolve git HEAD in $root`n$($head.text)" }
Add-Result PASS 'git-head' $head.text

$upstream = [string]$manifest.upstream_2026_5_base
$ancestor = Get-Git merge-base --is-ancestor $upstream HEAD
if ($ancestor.exit_code -eq 0) {
    Add-Result PASS 'upstream-ancestry' "HEAD descends from pinned upstream $upstream"
} else {
    Add-Result FAIL 'upstream-ancestry' "HEAD does not descend from pinned upstream $upstream, or the commit is missing locally"
}

$status = Get-Git status --porcelain=v1
if ($status.exit_code -eq 0 -and [string]::IsNullOrWhiteSpace($status.text)) {
    Add-Result PASS 'worktree' 'clean'
} elseif ($status.exit_code -eq 0) {
    Add-Result WARN 'worktree' 'dirty; acceptable only for an explicitly recorded local patch/build experiment'
} else {
    Add-Result FAIL 'worktree' $status.text
}

foreach ($rule in $manifest.required_anchors) {
    $relative = [string]$rule.path
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Result FAIL "anchor:$relative" "missing file; policy=$($rule.policy)"
        continue
    }
    $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    foreach ($anchor in $rule.anchors) {
        $needle = [string]$anchor
        if ($text.Contains($needle)) {
            Add-Result PASS "anchor:$relative" $needle
        } else {
            Add-Result FAIL "anchor:$relative" "missing '$needle'; policy=$($rule.policy)"
        }
    }
}

$versionsPath = Join-Path $root 'versions.mk'
if (-not (Test-Path -LiteralPath $versionsPath -PathType Leaf)) {
    Add-Result FAIL 'dependency-contract' 'versions.mk missing'
} else {
    $versions = Get-Content -LiteralPath $versionsPath -Raw -Encoding UTF8
    foreach ($needleObj in $manifest.dependency_contract.'versions.mk') {
        $needle = [string]$needleObj
        if ($versions.Contains($needle)) {
            Add-Result PASS 'dependency-contract' $needle
        } else {
            Add-Result FAIL 'dependency-contract' "versions.mk missing '$needle'"
        }
    }
}

foreach ($pending in $manifest.known_pending_local_patches) {
    Add-Result WARN "known-pending:$($pending.path)" ([string]$pending.description)
}

$failCount = @($results | Where-Object { $_.status -eq 'FAIL' }).Count
$warnCount = @($results | Where-Object { $_.status -eq 'WARN' }).Count
$passCount = @($results | Where-Object { $_.status -eq 'PASS' }).Count
$report = [ordered]@{
    schema_version = 1
    checked_at_utc = [DateTime]::UtcNow.ToString('o')
    repo_root = $root
    git_head = $head.text
    manifest = $manifestFile
    pinned_upstream = $upstream
    summary = [ordered]@{ pass = $passCount; warn = $warnCount; fail = $failCount }
    results = @($results)
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $fullOutput = [System.IO.Path]::GetFullPath($OutputPath)
    $parent = Split-Path -Parent $fullOutput
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $fullOutput -Encoding UTF8
    Write-Host "Audit report: $fullOutput"
}

Write-Host "Gemma4 forward-port audit: PASS=$passCount WARN=$warnCount FAIL=$failCount"
if ($failCount -gt 0) { exit 1 }
exit 0
