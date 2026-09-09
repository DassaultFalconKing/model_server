[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourceModelPath,
    [Parameter(Mandatory = $true)][string]$OverlayPath,
    [string]$GoogleModel = 'google/gemma-4-26B-A4B-it',
    [string]$GoogleRevision = '',
    [ValidateSet('Auto', 'HardLink', 'Copy')][string]$LinkMode = 'Auto',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-FullPath([string]$Path) {
    return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
}

function Test-GemmaIr([string]$Path) {
    $languageXml = Join-Path $Path 'openvino_language_model.xml'
    $genericXml = Join-Path $Path 'openvino_model.xml'
    if (-not (Test-Path -LiteralPath $languageXml) -and -not (Test-Path -LiteralPath $genericXml)) {
        throw "Source model does not contain openvino_language_model.xml or openvino_model.xml: $Path"
    }
}

$source = Resolve-FullPath $SourceModelPath
Test-GemmaIr $source

$overlayParent = Split-Path -Parent ([System.IO.Path]::GetFullPath($OverlayPath))
if (-not (Test-Path -LiteralPath $overlayParent)) {
    New-Item -ItemType Directory -Path $overlayParent -Force | Out-Null
}
$overlay = [System.IO.Path]::GetFullPath($OverlayPath)

if ($source.TrimEnd('\', '/') -ieq $overlay.TrimEnd('\', '/')) {
    throw 'OverlayPath must be different from SourceModelPath. The Wondernutts source model is immutable.'
}

if (Test-Path -LiteralPath $overlay) {
    if (-not $Force) {
        throw "Overlay already exists: $overlay. Use -Force to recreate it."
    }
    Remove-Item -LiteralPath $overlay -Recurse -Force
}
New-Item -ItemType Directory -Path $overlay -Force | Out-Null

$resolvedRevision = $GoogleRevision
if ([string]::IsNullOrWhiteSpace($resolvedRevision)) {
    $modelApi = "https://huggingface.co/api/models/$GoogleModel"
    Write-Host "Resolving latest Google template revision from $modelApi"
    $modelInfo = Invoke-RestMethod -Uri $modelApi -Method Get
    if (-not $modelInfo.sha) {
        throw "Hugging Face model API did not return an exact revision for $GoogleModel"
    }
    $resolvedRevision = [string]$modelInfo.sha
}

if ($resolvedRevision -notmatch '^[0-9a-fA-F]{40}$') {
    throw "Google revision must resolve to an exact 40-hex commit SHA, got: $resolvedRevision"
}

$templateUrl = "https://huggingface.co/$GoogleModel/resolve/$resolvedRevision/chat_template.jinja?download=true"
$templateTemp = Join-Path ([System.IO.Path]::GetTempPath()) ("gemma4-google-template-" + [Guid]::NewGuid().ToString('N') + '.jinja')
try {
    Write-Host "Downloading Google Gemma4 template at exact revision $resolvedRevision"
    Invoke-WebRequest -Uri $templateUrl -OutFile $templateTemp -UseBasicParsing
    $templateText = Get-Content -LiteralPath $templateTemp -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($templateText)) {
        throw 'Downloaded Google chat_template.jinja is empty.'
    }
    foreach ($marker in @('<|tool_call>call:', '<|tool_response>')) {
        if (-not $templateText.Contains($marker)) {
            throw "Downloaded Google template is missing required Gemma4 marker: $marker"
        }
    }

    $sourceRoot = [System.IO.Path]::GetFullPath($source).TrimEnd('\', '/')
    $sameVolume = ([System.IO.Path]::GetPathRoot($sourceRoot) -ieq [System.IO.Path]::GetPathRoot($overlay))
    $largeCopyLimit = 64MB

    Get-ChildItem -LiteralPath $sourceRoot -Recurse -Force | ForEach-Object {
        $relative = $_.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
        if ([string]::IsNullOrEmpty($relative)) { return }
        $dest = Join-Path $overlay $relative

        if ($_.PSIsContainer) {
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            return
        }

        if ($relative -ieq 'chat_template.jinja') {
            # Deliberately do not propagate Wondernutts' template.
            return
        }

        $destParent = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
        }

        $linked = $false
        if ($LinkMode -ne 'Copy' -and $sameVolume) {
            try {
                New-Item -ItemType HardLink -Path $dest -Target $_.FullName -ErrorAction Stop | Out-Null
                $linked = $true
            } catch {
                if ($LinkMode -eq 'HardLink') { throw }
            }
        } elseif ($LinkMode -eq 'HardLink') {
            throw 'HardLink mode requires source and overlay on the same filesystem volume.'
        }

        if (-not $linked) {
            if ($LinkMode -eq 'Auto' -and $_.Length -gt $largeCopyLimit) {
                throw "Hardlink failed/unavailable for large model file '$relative' ($($_.Length) bytes). Put overlay on the same NTFS volume or use -LinkMode Copy explicitly."
            }
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
        }
    }

    $templateDest = Join-Path $overlay 'chat_template.jinja'
    Copy-Item -LiteralPath $templateTemp -Destination $templateDest -Force
    $templateHash = (Get-FileHash -LiteralPath $templateDest -Algorithm SHA256).Hash.ToLowerInvariant()

    $sourceTemplate = Join-Path $source 'chat_template.jinja'
    $sourceTemplateHash = if (Test-Path -LiteralPath $sourceTemplate) {
        (Get-FileHash -LiteralPath $sourceTemplate -Algorithm SHA256).Hash.ToLowerInvariant()
    } else { $null }

    $provenance = [ordered]@{
        schema_version = 1
        prepared_at_utc = [DateTime]::UtcNow.ToString('o')
        source_model_path = $source
        overlay_path = $overlay
        weights_authority = 'Wondernutts IR/weights only'
        source_template_used = $false
        source_template_sha256 = $sourceTemplateHash
        google_model = $GoogleModel
        google_revision = $resolvedRevision.ToLowerInvariant()
        google_template_url = $templateUrl
        google_template_sha256 = $templateHash
        link_mode_requested = $LinkMode
        source_and_overlay_same_volume = $sameVolume
    }
    $provenancePath = Join-Path $overlay 'gemma4-template-provenance.json'
    $provenance | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $provenancePath -Encoding UTF8

    Write-Host "Gemma4 Google-template overlay prepared"
    Write-Host "  source:        $source"
    Write-Host "  overlay:       $overlay"
    Write-Host "  Google rev:    $resolvedRevision"
    Write-Host "  template SHA:  $templateHash"
    Write-Host "  provenance:    $provenancePath"
} finally {
    if (Test-Path -LiteralPath $templateTemp) {
        Remove-Item -LiteralPath $templateTemp -Force -ErrorAction SilentlyContinue
    }
}
