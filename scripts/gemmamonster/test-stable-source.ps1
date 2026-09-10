[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [ValidateSet('maintainer-rc2','known-good-rc1')][string]$RuntimeProfile = 'maintainer-rc2',
    [string]$ShortRoot = '',
    [string]$Gemma4TokenizerPath = '',
    [switch]$NoPython,
    [string]$LogPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'stable-runtime-profiles.ps1')

function Get-Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$profile = Get-GemmamonsterStableRuntimeProfile -Name $RuntimeProfile
if ([string]::IsNullOrWhiteSpace($ShortRoot)) { $ShortRoot = [string]$profile.default_short_root }
$depRoot = "C:\$ShortRoot\openvino"
if (-not (Test-Path -LiteralPath $depRoot -PathType Container)) { throw "Runtime dependency root missing: $depRoot" }
$linkItem = Get-Item -LiteralPath $depRoot -Force
$linkTarget = [string]($linkItem.Target -join ';')
if ($linkTarget -notlike "*$($profile.package_marker)*") {
    throw "Runtime root does not match requested profile '$RuntimeProfile': $linkTarget"
}

$workspacePath = (Resolve-Path -LiteralPath (Join-Path $root 'WORKSPACE')).Path
$workspaceOriginalBytes = [System.IO.File]::ReadAllBytes($workspacePath)
$workspaceOriginalHash = Get-Hash $workspacePath
$workspaceText = [System.Text.Encoding]::UTF8.GetString($workspaceOriginalBytes)
$defaultOpenVinoLiteral = 'C:\\opt\\openvino\\runtime'
$profileOpenVinoLiteral = "C:\\$ShortRoot\\openvino\\runtime"
if (-not $workspaceText.Contains($defaultOpenVinoLiteral)) {
    throw "WORKSPACE does not contain expected Windows OpenVINO authority path '$defaultOpenVinoLiteral'; refusing an unproven rewrite."
}
$profileWorkspaceText = $workspaceText.Replace($defaultOpenVinoLiteral, $profileOpenVinoLiteral)
if ($profileWorkspaceText -eq $workspaceText) {
    throw "WORKSPACE runtime-profile rewrite made no change for C:\$ShortRoot."
}

if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $logDir = Join-Path $root 'tmp\gemmamonster-contracts'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $LogPath = Join-Path $logDir ("contracts-$RuntimeProfile-" + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '.log')
}

$targets = @(
    '//src/test/llm/gemma4_fast:gemma4_parser_contract_test',
    '//src/test/llm/generation_config:gemma4_generation_contract_test',
    '//src/test/llm/generation_config:gemma4_prompt_state_generation_contract_test',
    '//src/test/llm/generation_config:openai_parallel_tool_calls_contract_test',
    '//src/test/llm/gemma4_overlay:gemma4_chat_template_overlay_contract_test',
    '//src/test/llm/gemma4_overlay:gemma4_google_jinja_contract_test'
)
$config = if ($NoPython) { 'win_mp_on_py_off' } else { 'win_mp_on_py_on' }
$openvinoDir = "C:\$ShortRoot\openvino\runtime\cmake"
$setupvars = "C:\$ShortRoot\openvino\setupvars.bat"
$opencvSetup = 'C:\opt\opencv_4.14.0\setup_vars_opencv4.cmd'
if (-not (Test-Path -LiteralPath $setupvars -PathType Leaf)) { throw "OpenVINO setupvars missing: $setupvars" }
if (-not (Test-Path -LiteralPath $opencvSetup -PathType Leaf)) { throw "OpenCV setup script missing: $opencvSetup" }

$oldTokenizer = $env:GEMMA4_TOKENIZER_PATH
$workspaceRestored = $false
try {
    [System.IO.File]::WriteAllText($workspacePath, $profileWorkspaceText, [System.Text.UTF8Encoding]::new($false))
    $activeWorkspace = Get-Content -LiteralPath $workspacePath -Raw -Encoding UTF8
    if (-not $activeWorkspace.Contains($profileOpenVinoLiteral)) {
        throw "WORKSPACE was not rebound to selected runtime profile C:\$ShortRoot."
    }
    if ($activeWorkspace.Contains($defaultOpenVinoLiteral)) {
        throw 'WORKSPACE still contains C:\opt\openvino\runtime after profile binding; source contract provenance is ambiguous.'
    }

    if (-not [string]::IsNullOrWhiteSpace($Gemma4TokenizerPath)) {
        $env:GEMMA4_TOKENIZER_PATH = (Resolve-Path -LiteralPath $Gemma4TokenizerPath).Path
    }

    $targetText = $targets -join ' '
    # Contract test binaries need the selected runtime's DLLs on THEIR PATH.
    # env_inherit reads the bazel SERVER env (stale, from build time), not the
    # client cmd env, so setupvars in the chain below never reaches the tests.
    # Proven by env bisect: bins-on-PATH starts the binary (exit 1, tests run),
    # PYTHONHOME/USERPROFILE do not matter for the AV. Pass explicit test env.
    $testBinPath = "C:\$ShortRoot\openvino\runtime\bin\intel64\Release;C:\$ShortRoot\openvino\runtime\3rdparty\tbb\bin"
    $testPathValue = "$testBinPath;C:\opt\Python312;" + $env:PATH
    $cmd = "call `"$setupvars`" && call `"$opencvSetup`" && set `"BAZEL_SH=C:\opt\msys64\usr\bin\bash.exe`" && set `"PYTHONHOME=C:\opt\Python312`" && bazel --output_user_root=C:\$ShortRoot test --config=$config --action_env OpenVINO_DIR=$openvinoDir --test_env=PYTHONHOME=C:\opt\Python312 --test_env=`"PATH=$testPathValue`" --test_output=errors --verbose_failures $targetText"
    Write-Host "Running GEMMAMONSTER source contracts on $RuntimeProfile"
    Write-Host "  HEAD: $((& git -C $root rev-parse HEAD).Trim())"
    Write-Host "  dependency root: C:\$ShortRoot"
    Write-Host "  WORKSPACE OpenVINO path: $profileOpenVinoLiteral"
    Write-Host "  log: $LogPath"
    Push-Location $root
    try {
        & cmd.exe /d /s /c $cmd 2>&1 | Tee-Object -FilePath $LogPath
        $rc = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($rc -ne 0) { throw "GEMMAMONSTER source contracts FAILED with exit code $rc. See $LogPath" }
} finally {
    [System.IO.File]::WriteAllBytes($workspacePath, $workspaceOriginalBytes)
    $workspaceRestored = ((Get-Hash $workspacePath) -eq $workspaceOriginalHash)
    if ($null -eq $oldTokenizer) { Remove-Item Env:GEMMA4_TOKENIZER_PATH -ErrorAction SilentlyContinue }
    else { $env:GEMMA4_TOKENIZER_PATH = $oldTokenizer }
}

if (-not $workspaceRestored) {
    throw 'WORKSPACE was not restored byte-for-byte after source contract execution.'
}
$postStatus = @(& git -C $root status --porcelain | Where-Object { $_ -notmatch '^\?\? bazel-[^/]*/$' })
if ($postStatus.Count -gt 0) {
    throw "Source contract runner left the working tree dirty:`n$($postStatus -join "`n")"
}

Write-Host 'GEMMAMONSTER_SOURCE_CONTRACTS_PASS'
Write-Host "  runtime_profile: $RuntimeProfile"
Write-Host "  log: $LogPath"
Write-Host '  workspace_restored_byte_exact: true'
