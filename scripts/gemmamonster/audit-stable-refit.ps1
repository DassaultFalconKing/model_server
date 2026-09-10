[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [string]$Ancestor = '9eb93f15fecb848d399f17c7a6a6626e5a1498d7',
    [string]$AdvancedRef = 'fde0762ba314dc5f6448726dfce7c533bad9a8a6',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'stable-runtime-profiles.ps1')

function Git([string[]]$GitArgs, [switch]$AllowFailure) {
    $out = & git.exe -C $root @GitArgs 2>&1
    $rc = $LASTEXITCODE
    if ($rc -ne 0 -and -not $AllowFailure) { throw "git $($GitArgs -join ' ') failed ($rc): $($out -join ' ')" }
    return [pscustomobject]@{ ExitCode=$rc; Output=(($out | Out-String).Trim()) }
}

function File-ExistsAtHead([string]$Path) {
    return (Git @('cat-file','-e',"HEAD:$Path") -AllowFailure).ExitCode -eq 0
}

function Changed-FromAncestor([string]$Path) {
    & git.exe -C $root diff --quiet "$Ancestor..HEAD" -- $Path
    return $LASTEXITCODE -ne 0
}

function Blob-At([string]$Ref, [string]$Path) {
    $r = Git @('rev-parse',"$Ref`:$Path") -AllowFailure
    if ($r.ExitCode -ne 0) { return $null }
    return $r.Output
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$head = (Git @('rev-parse','HEAD')).Output
$tree = (Git @('rev-parse','HEAD^{tree}')).Output
$branch = (Git @('rev-parse','--abbrev-ref','HEAD')).Output

$ancestorCheck = Git @('merge-base','--is-ancestor',$Ancestor,$head) -AllowFailure
if ($ancestorCheck.ExitCode -ne 0) { throw "HEAD $head does not descend from required latest-maintainer 2026.4 ancestor $Ancestor" }
$mergeBase = (Git @('merge-base',$Ancestor,$head)).Output
if ($mergeBase -ne $Ancestor) { throw "Unexpected merge-base: expected=$Ancestor actual=$mergeBase" }

$advancedAvailable = (Git @('cat-file','-e',"$AdvancedRef^{commit}") -AllowFailure).ExitCode -eq 0
$berichtPath = 'docs/gemmamonster/Bericht-Provenance-Descendance-diff.md'

$runtimeFiles = @(
    'src/llm/apis/openai_api_handler.hpp',
    'src/llm/apis/openai_completions.hpp',
    'src/llm/apis/openai_request.hpp',
    'src/llm/apis/openai_responses.cpp',
    'src/llm/apis/openai_responses.hpp',
    'src/llm/io_processing/base_generation_config_builder.hpp',
    'src/llm/io_processing/chat_template/analyzer.cpp',
    'src/llm/io_processing/chat_template/caps.hpp',
    'src/llm/io_processing/gemma4/gemma4_reasoning_parser.cpp',
    'src/llm/io_processing/gemma4/gemma4_reasoning_parser.hpp',
    'src/llm/io_processing/gemma4/gemma4_tool_parser.cpp',
    'src/llm/io_processing/gemma4/gemma4_tool_parser.hpp',
    'src/llm/io_processing/generation_config_builder.hpp',
    'src/llm/io_processing/input_processors/chat_template_adapter.cpp',
    'src/llm/io_processing/input_processors/chat_template_adapter.hpp',
    'src/llm/io_processing/input_processors/chat_template_processor.cpp',
    'src/llm/io_processing/input_processors/chat_template_processor.hpp',
    'src/llm/io_processing/output_parser.cpp',
    'src/llm/io_processing/output_parsing_config.hpp',
    'src/llm/ovms_text_streamer.cpp',
    'src/llm/servable.cpp',
    'src/llm/servable.hpp'
)

$contractFiles = @(
    'src/test/llm/gemma4_fast/BUILD',
    'src/test/llm/gemma4_fast/gemma4_parser_contract_test.cpp',
    'src/test/llm/gemma4_fast/gemma4_reasoning_semantic_refit_test.cpp',
    'src/test/llm/gemma4_fast/gemma4_recovery_contract_test.cpp',
    'src/test/llm/gemma4_overlay/BUILD',
    'src/test/llm/gemma4_overlay/gemma4_chat_template_overlay_contract_test.cpp',
    'src/test/llm/gemma4_overlay/gemma4_google_jinja_contract_test.cpp',
    'src/test/llm/generation_config/BUILD',
    'src/test/llm/generation_config/gemma4_generation_contract_test.cpp',
    'src/test/llm/generation_config/gemma4_prompt_state_generation_contract_test.cpp',
    'src/test/llm/generation_config/openai_parallel_tool_calls_contract_test.cpp',
    'tests/windows/gemma4_standalone_package_test.ps1',
    'tests/windows/gemmamonster_stable_candidate_contract_test.ps1'
)

$buildReadyFiles = @(
    $berichtPath,
    'docs/gemmamonster/STABLE-2026.4-REFIT-HANDOFF.md',
    'scripts/gemmamonster/stable-runtime-profiles.ps1',
    'scripts/gemmamonster/Test-StableCandidate.ps1',
    'scripts/gemmamonster/audit-stable-refit.ps1',
    'scripts/gemmamonster/build-stable-candidate.ps1',
    'scripts/gemmamonster/test-stable-source.ps1',
    'scripts/gemmamonster/launch-stable-candidate.ps1',
    'windows_build.bat',
    'windows_create_package.bat',
    'windows_install_build_dependencies.bat',
    'versions.mk'
)

$failures = New-Object System.Collections.Generic.List[string]
$rows = New-Object System.Collections.Generic.List[object]
foreach ($path in $runtimeFiles) {
    $present = File-ExistsAtHead $path
    $changed = if ($present) { Changed-FromAncestor $path } else { $false }
    if (-not $present) { $failures.Add("missing runtime blast-radius file: $path") }
    elseif (-not $changed) { $failures.Add("runtime blast-radius file is unchanged from ancestor: $path") }

    $headBlob = if ($present) { Blob-At 'HEAD' $path } else { $null }
    $advancedBlob = if ($advancedAvailable) { Blob-At $AdvancedRef $path } else { $null }
    $rows.Add([ordered]@{
        path = $path
        class = 'runtime'
        present = $present
        changed_from_ancestor = $changed
        head_blob = $headBlob
        advanced_blob = $advancedBlob
        advanced_relation = if (-not $advancedAvailable) { 'ADVANCED_REF_UNAVAILABLE' } elseif ($null -eq $advancedBlob) { 'NOT_IN_ADVANCED_REF' } elseif ($headBlob -eq $advancedBlob) { 'BYTE_EXACT' } else { 'REFIT_DIFFERS' }
    })
}

foreach ($path in $contractFiles) {
    $present = File-ExistsAtHead $path
    if (-not $present) { $failures.Add("missing contract file: $path") }
    $rows.Add([ordered]@{path=$path;class='contract';present=$present;changed_from_ancestor=if($present){Changed-FromAncestor $path}else{$false}})
}
foreach ($path in $buildReadyFiles) {
    $present = File-ExistsAtHead $path
    if (-not $present) { $failures.Add("missing build-ready file: $path") }
    $rows.Add([ordered]@{path=$path;class='build-ready';present=$present;changed_from_ancestor=if($present){Changed-FromAncestor $path}else{$false}})
}

if ($advancedAvailable -and (File-ExistsAtHead $berichtPath)) {
    $currentBerichtBlob = Blob-At 'HEAD' $berichtPath
    $advancedBerichtBlob = Blob-At $AdvancedRef $berichtPath
    if ($null -eq $advancedBerichtBlob) {
        $failures.Add("advanced ref does not contain required provenance Bericht: $berichtPath")
    } elseif ($currentBerichtBlob -ne $advancedBerichtBlob) {
        $failures.Add("provenance Bericht is not byte-exact with ${AdvancedRef}: current=$currentBerichtBlob advanced=$advancedBerichtBlob")
    }
}

$versionsPath = Join-Path $root 'versions.mk'
$versionsText = Get-Content -LiteralPath $versionsPath -Raw -Encoding UTF8
$rc2 = Get-GemmamonsterStableRuntimeProfile -Name 'maintainer-rc2'
foreach ($pair in @(
    @('OV_SOURCE_BRANCH',$rc2.OV_SOURCE_BRANCH),
    @('OV_TOKENIZERS_BRANCH',$rc2.OV_TOKENIZERS_BRANCH),
    @('OV_GENAI_BRANCH',$rc2.OV_GENAI_BRANCH),
    @('GENAI_PACKAGE_URL_WINDOWS',$rc2.GENAI_PACKAGE_URL_WINDOWS),
    @('PYTHON_VERSION',$rc2.PYTHON_VERSION),
    @('OPTIMUM_VERSION',$rc2.OPTIMUM_VERSION),
    @('OPTIMUM_INTEL_VERSION',$rc2.OPTIMUM_INTEL_VERSION),
    @('OPTIMUM_OPENVINO_VERSION',$rc2.OPTIMUM_OPENVINO_VERSION),
    @('OPTIMUM_OPENVINO_TOKENIZERS_VERSION',$rc2.OPTIMUM_OPENVINO_TOKENIZERS_VERSION)
)) {
    $name=$pair[0]; $value=$pair[1]
    if ($versionsText -notmatch "(?m)^$([regex]::Escape($name))\s*\?=\s*$([regex]::Escape($value))\s*$") {
        $failures.Add("versions.mk exact RC2 authority mismatch: $name")
    }
}
if ($versionsText -match '2026\.5') { $failures.Add('versions.mk contains 2026.5 marker') }

$dirty = @(& git.exe -C $root status --porcelain)
if ($dirty.Count -gt 0) { $failures.Add("working tree is dirty: $($dirty -join '; ')") }

$report = [ordered]@{
    schema_version = 2
    checked_at_utc = [DateTime]::UtcNow.ToString('o')
    repository = 'DassaultFalconKing/model_server'
    branch = $branch
    head = $head
    tree = $tree
    ancestor = $Ancestor
    merge_base = $mergeBase
    advanced_ref = $AdvancedRef
    advanced_ref_available = $advancedAvailable
    bericht = [ordered]@{
        path = $berichtPath
        present = File-ExistsAtHead $berichtPath
        head_blob = if (File-ExistsAtHead $berichtPath) { Blob-At 'HEAD' $berichtPath } else { $null }
        advanced_blob = if ($advancedAvailable) { Blob-At $AdvancedRef $berichtPath } else { $null }
    }
    authority_note = 'Bericht provenance union is broader than current diff; this gate validates the active functional/build-ready subset and requires the exact fde0762 Bericht when that ref is available.'
    rows = $rows.ToArray()
    failures = $failures.ToArray()
    verdict = if ($failures.Count -eq 0) { 'BUILD_READY_SOURCE_AUDIT_PASS' } else { 'BUILD_READY_SOURCE_AUDIT_FAIL' }
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $root 'tmp\gemmamonster-refit-audit.json'
}
$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

Write-Host "GEMMAMONSTER_STABLE_REFIT_AUDIT verdict=$($report.verdict)"
Write-Host "  HEAD:         $head"
Write-Host "  ancestor:     $Ancestor"
Write-Host "  advanced_ref: $AdvancedRef available=$advancedAvailable"
Write-Host "  Bericht:      $($report.bericht.head_blob)"
Write-Host "  report:       $OutputPath"
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "  FAIL: $failure" }
    throw "Stable refit audit failed with $($failures.Count) finding(s)."
}
