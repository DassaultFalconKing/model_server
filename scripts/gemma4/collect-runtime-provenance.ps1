[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OvmsPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$OpenVinoDir = $env:OpenVINO_DIR,
    [string]$RepoPath = '',
    [string]$TemplateProvenancePath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-FileRecord([System.IO.FileInfo]$File) {
    return [ordered]@{
        path = $File.FullName
        size = $File.Length
        sha256 = (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        file_version = $File.VersionInfo.FileVersion
        product_version = $File.VersionInfo.ProductVersion
    }
}

$ovms = Get-Item -LiteralPath $OvmsPath
if ($ovms.PSIsContainer) { throw "OvmsPath must point to ovms.exe: $OvmsPath" }

$runtimeRoots = New-Object System.Collections.Generic.List[string]
if (-not [string]::IsNullOrWhiteSpace($OpenVinoDir) -and (Test-Path -LiteralPath $OpenVinoDir)) {
    $runtimeRoots.Add((Resolve-Path -LiteralPath $OpenVinoDir).Path)
}
$ovmsDir = $ovms.Directory.FullName
if (-not $runtimeRoots.Contains($ovmsDir)) { $runtimeRoots.Add($ovmsDir) }

$dlls = @{}
foreach ($root in $runtimeRoots) {
    Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(openvino|openvino_genai).*\.dll$' } |
        ForEach-Object { $dlls[$_.FullName.ToLowerInvariant()] = $_ }
}

$gitHead = $null
$gitBranch = $null
if (-not [string]::IsNullOrWhiteSpace($RepoPath) -and (Test-Path -LiteralPath $RepoPath)) {
    try {
        $gitHead = (& git -C $RepoPath rev-parse HEAD 2>$null).Trim()
        $gitBranch = (& git -C $RepoPath branch --show-current 2>$null).Trim()
    } catch { }
}

$versionOutput = $null
try {
    $versionOutput = (& $ovms.FullName --version 2>&1 | Out-String).Trim()
} catch {
    $versionOutput = "<failed: $($_.Exception.Message)>"
}

$templateProvenance = $null
if (-not [string]::IsNullOrWhiteSpace($TemplateProvenancePath) -and (Test-Path -LiteralPath $TemplateProvenancePath)) {
    $templateProvenance = Get-Content -LiteralPath $TemplateProvenancePath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$record = [ordered]@{
    schema_version = 1
    captured_at_utc = [DateTime]::UtcNow.ToString('o')
    host = [ordered]@{
        computer_name = $env:COMPUTERNAME
        os = [System.Environment]::OSVersion.VersionString
        process_architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    }
    ovms = [ordered]@{
        path = $ovms.FullName
        sha256 = (Get-FileHash -LiteralPath $ovms.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        file_version = $ovms.VersionInfo.FileVersion
        product_version = $ovms.VersionInfo.ProductVersion
        version_output = $versionOutput
    }
    source = [ordered]@{
        repo_path = if ($RepoPath) { [System.IO.Path]::GetFullPath($RepoPath) } else { $null }
        git_branch = $gitBranch
        git_head = $gitHead
    }
    runtime = [ordered]@{
        openvino_dir = $OpenVinoDir
        search_roots = @($runtimeRoots)
        dlls = @($dlls.Values | Sort-Object FullName | ForEach-Object { Get-FileRecord $_ })
    }
    template = $templateProvenance
}

$outParent = Split-Path -Parent ([System.IO.Path]::GetFullPath($OutputPath))
if ($outParent -and -not (Test-Path -LiteralPath $outParent)) {
    New-Item -ItemType Directory -Path $outParent -Force | Out-Null
}
$record | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "Runtime provenance written: $OutputPath"
Write-Host "OVMS SHA256: $($record.ovms.sha256)"
Write-Host "Runtime DLLs recorded: $($record.runtime.dlls.Count)"
