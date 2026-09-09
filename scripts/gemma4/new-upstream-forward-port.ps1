[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$OverlayRef,
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [string]$UpstreamRemote = 'upstream',
    [string]$UpstreamRef = 'main',
    [string]$BranchName = '',
    [switch]$ApplySafeCopies
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$manifestPath = Join-Path $PSScriptRoot 'forward-port-manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Run-Git([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args) {
    & git -C $root @Args
    if ($LASTEXITCODE -ne 0) { throw "git failed: git -C $root $($Args -join ' ')" }
}
function Git-Text([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args) {
    $text = (& git -C $root @Args 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "git failed: git -C $root $($Args -join ' ')`n$text" }
    return $text
}

$dirty = (& git -C $root status --porcelain=v1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect worktree status.' }
if (-not [string]::IsNullOrWhiteSpace($dirty)) { throw 'Forward-port bootstrap requires a clean worktree.' }

$remotes = @(Git-Text remote -v)
if (-not (($remotes -join "`n") -match "(?m)^$([regex]::Escape($UpstreamRemote))\s")) {
    throw "Missing '$UpstreamRemote' remote. Add the official openvinotoolkit/model_server remote explicitly before running this script."
}

Write-Host "Fetching $UpstreamRemote/$UpstreamRef and origin"
Run-Git fetch $UpstreamRemote $UpstreamRef
Run-Git fetch origin
$upstreamSha = Git-Text rev-parse "$UpstreamRemote/$UpstreamRef^{commit}"
$overlaySha = Git-Text rev-parse "$OverlayRef^{commit}"
if ([string]::IsNullOrWhiteSpace($BranchName)) { $BranchName = "integration/ovms-$Version-forward-port" }

$existing = (& git -C $root show-ref --verify --quiet "refs/heads/$BranchName"; $LASTEXITCODE)
if ($existing -eq 0) { throw "Local branch already exists: $BranchName" }

Write-Host "Creating $BranchName from exact upstream $upstreamSha"
Run-Git switch -c $BranchName $upstreamSha

$copied = New-Object System.Collections.Generic.List[string]
$missingSafe = New-Object System.Collections.Generic.List[string]
if ($ApplySafeCopies) {
    foreach ($pathObj in $manifest.safe_copy_on_future_forward_port) {
        $path = [string]$pathObj
        & git -C $root cat-file -e "$overlaySha`:$path" 2>$null
        if ($LASTEXITCODE -ne 0) {
            $missingSafe.Add($path)
            Write-Warning "Safe-copy path is absent in overlay ref: $path"
            continue
        }
        Run-Git checkout $overlaySha -- $path
        $copied.Add($path)
        Write-Host "SAFE_COPY $path"
    }
}

$manual = @($manifest.manual_compose_on_future_forward_port | ForEach-Object { [string]$_ })
$outDir = Join-Path $root ("tmp\gemmamonster-forward-port\" + $Version)
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$report = [ordered]@{
    schema_version = 1
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    branch = $BranchName
    upstream_remote = $UpstreamRemote
    upstream_ref = $UpstreamRef
    upstream_sha = $upstreamSha
    overlay_ref = $OverlayRef
    overlay_sha = $overlaySha
    safe_copies_applied = @($copied)
    safe_copy_missing = @($missingSafe)
    manual_compose = $manual
    upstream_owned = @($manifest.upstream_owned)
    known_pending_local_patches = @($manifest.known_pending_local_patches)
    next_steps = @(
        'Inspect each MANUAL_COMPOSE path against both upstream_sha and overlay_sha.',
        'Preserve upstream generic behavior; transplant only the Gemmamonster semantic contract.',
        'Add/port contract tests before changing production code when the new upstream shape requires adaptation.',
        'Run scripts/gemma4/audit-forward-port.ps1; do not build until FAIL=0.',
        'Build and run live acceptance; never promote based on static audit alone.'
    )
}
$reportPath = Join-Path $outDir 'forward-port-bootstrap.json'
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8

Write-Host ''
Write-Host 'FORWARD-PORT WORKTREE BOOTSTRAPPED'
Write-Host "  branch:       $BranchName"
Write-Host "  upstream:     $upstreamSha"
Write-Host "  overlay:      $overlaySha"
Write-Host "  safe copied:  $($copied.Count)"
Write-Host "  manual paths: $($manual.Count)"
Write-Host "  report:       $reportPath"
Write-Host 'No commit and no push were performed.'
