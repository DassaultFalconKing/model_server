param(
    [ValidateSet("Dev", "Verify", "Package")]
    [string]$Mode = "Dev",

    [bool]$WithPython = $true,

    [ValidateRange(0, 256)]
    [int]$Jobs = 0,

    [string]$OutputUserRoot = "C:\opt",
    [string]$DiskCache = "C:\opt\bazel-disk-cache\win_mp_on_py_on",
    [string]$RepositoryCache = "C:\opt\bazel-repository-cache",
    [string]$ProfileDirectory = "C:\opt\bazel-profiles",
    [string]$OpenVinoDir = "",
    [string]$OpenCvDir = "",

    [switch]$SkipFastTests,
    [switch]$NoStamp,
    [switch]$NoTranscript
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RepoRoot

function Get-DependencyVersion([string]$Name) {
    $line = Get-Content -LiteralPath (Join-Path $RepoRoot "versions.mk") |
        Where-Object { $_ -match "^\s*$([regex]::Escape($Name))\s*\?=\s*(\S+)" } |
        Select-Object -First 1
    if (-not $line) {
        throw "Could not resolve $Name from versions.mk"
    }
    if ($line -notmatch "^\s*$([regex]::Escape($Name))\s*\?=\s*(\S+)") {
        throw "Could not parse $Name from versions.mk"
    }
    return $Matches[1]
}

function Initialize-MsvcForBazel {
    if ($env:BAZEL_VS -and (Test-Path -LiteralPath $env:BAZEL_VS -PathType Container)) {
        $vsPath = $env:BAZEL_VS
    } else {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
        $vsPath = $null
        if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
            $detected = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
            if ($LASTEXITCODE -eq 0 -and $detected) {
                $vsPath = ($detected | Select-Object -First 1).Trim()
            }
        }
        if (-not $vsPath) {
            foreach ($candidate in @(
                "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools",
                "C:\Program Files\Microsoft Visual Studio\2022\Community",
                "C:\Program Files\Microsoft Visual Studio\2022\Professional",
                "C:\Program Files\Microsoft Visual Studio\2022\Enterprise"
            )) {
                if (Test-Path -LiteralPath (Join-Path $candidate "VC") -PathType Container) {
                    $vsPath = $candidate
                    break
                }
            }
        }
        if (-not $vsPath) {
            throw "MSVC with VC.Tools.x86.x64 was not found. Install Visual Studio 2022 Build Tools or set BAZEL_VS."
        }
        $env:BAZEL_VS = $vsPath
    }

    $env:BAZEL_VC = Join-Path $vsPath "VC"
    $versionFile = Join-Path $env:BAZEL_VC "Auxiliary\Build\Microsoft.VCToolsVersion.default.txt"
    if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
        $detectedVersion = (Get-Content -Raw -LiteralPath $versionFile).Trim()
        if ($detectedVersion) {
            $env:BAZEL_VC_FULL_VERSION = $detectedVersion
        }
    }

    Write-Host "MSVC: $($env:BAZEL_VS)"
    if ($env:BAZEL_VC_FULL_VERSION) {
        Write-Host "VC tools: $($env:BAZEL_VC_FULL_VERSION)"
    }
}

function Import-BatchEnvironment([string]$BatchFile) {
    if (-not (Test-Path -LiteralPath $BatchFile -PathType Leaf)) {
        throw "Environment setup script not found: $BatchFile"
    }
    $command = "call `"$BatchFile`" >nul && set"
    $lines = & $env:ComSpec /d /s /c $command
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Environment setup failed ($exitCode): $BatchFile"
    }
    foreach ($line in $lines) {
        $separator = $line.IndexOf('=')
        if ($separator -le 0) { continue }
        $name = $line.Substring(0, $separator)
        $value = $line.Substring($separator + 1)
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

function Invoke-BazelStep(
    [string]$Command,
    [string]$Name,
    [string[]]$Targets,
    [string[]]$ExtraArgs = @()
) {
    $safeName = $Name -replace '[^A-Za-z0-9_.-]', '_'
    $profile = Join-Path $ProfileDirectory ("{0}-{1}.json.gz" -f $script:Stamp, $safeName)

    $args = @(
        "--output_user_root=$OutputUserRoot",
        $Command,
        "--config=$script:BazelConfig",
        "--disk_cache=$DiskCache",
        "--repository_cache=$RepositoryCache",
        "--profile=$profile",
        "--action_env", "OpenVINO_DIR=$OpenVinoDir",
        "--action_env", "OpenCV_DIR=$OpenCvDir",
        "--verbose_failures"
    )
    if ($Jobs -gt 0) {
        $args += "--jobs=$Jobs"
    }
    $args += $ExtraArgs
    $args += $Targets

    Write-Host ""
    Write-Host "[$Name] bazel $($args -join ' ')"
    $stepWatch = [System.Diagnostics.Stopwatch]::StartNew()
    & bazel @args
    $exitCode = $LASTEXITCODE
    $stepWatch.Stop()
    Write-Host "[$Name] exit=$exitCode elapsed=$($stepWatch.Elapsed) profile=$profile"
    if ($exitCode -ne 0) {
        throw "$Name failed with exit code $exitCode"
    }
}

function Invoke-Package {
    if ([System.IO.Path]::GetFullPath($OutputUserRoot).TrimEnd('\\') -ne 'C:\opt') {
        throw "Package mode currently expects -OutputUserRoot C:\opt because windows_create_package.bat addresses dependencies as C:\<root>."
    }
    $args = @("opt")
    if ($WithPython) {
        $args += "--with_python"
    }
    Write-Host ""
    Write-Host "[package] windows_create_package.bat $($args -join ' ')"
    & cmd.exe /d /s /c "windows_create_package.bat $($args -join ' ')"
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Package creation failed with exit code $exitCode"
    }
}

$script:Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:BazelConfig = if ($WithPython) { "win_mp_on_py_on" } else { "win_mp_on_py_off" }

if (-not $OpenVinoDir) {
    $OpenVinoDir = Join-Path $OutputUserRoot "openvino\runtime\cmake"
}
if (-not $OpenCvDir) {
    $opencvVersion = Get-DependencyVersion "OPENCV_VERSION"
    $OpenCvDir = "C:\opt\opencv_$opencvVersion"
}

foreach ($directory in @($DiskCache, $RepositoryCache, $ProfileDirectory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

$transcriptPath = Join-Path $ProfileDirectory ("{0}-windows-build-fast.log" -f $script:Stamp)
if (-not $NoTranscript) {
    Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null
}

$versionPath = Join-Path $RepoRoot "src\version.hpp"
$originalVersion = $null
$versionWasTemporarilyStamped = $false
$overallWatch = [System.Diagnostics.Stopwatch]::StartNew()

try {
    if (-not (Get-Command bazel -ErrorAction SilentlyContinue)) {
        throw "bazel was not found on PATH"
    }

    Initialize-MsvcForBazel

    $pythonRoot = "C:\opt\Python312"
    if ($WithPython -and (Test-Path -LiteralPath $pythonRoot -PathType Container)) {
        $env:PYTHONHOME = $pythonRoot
        $env:PATH = "$pythonRoot;$pythonRoot\Scripts;$env:PATH"
    }
    $msysBin = "C:\opt\msys64\usr\bin"
    if (Test-Path -LiteralPath $msysBin -PathType Container) {
        $env:BAZEL_SH = Join-Path $msysBin "bash.exe"
        $env:PATH = "$msysBin;$env:PATH"
    }

    $openvinoSetup = Join-Path (Split-Path (Split-Path $OpenVinoDir -Parent) -Parent) "setupvars.bat"
    Import-BatchEnvironment $openvinoSetup
    $opencvSetup = Join-Path $OpenCvDir "setup_vars_opencv4.cmd"
    Import-BatchEnvironment $opencvSetup

    if ($Mode -ne "Dev" -and -not $NoStamp) {
        $originalVersion = Get-Content -Raw -LiteralPath $versionPath
        if ($originalVersion.Contains("REPLACE_PROJECT_VERSION") -and $originalVersion.Contains("REPLACE_BAZEL_BUILD_FLAGS")) {
            $shortSha = (& git rev-parse --short HEAD).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $shortSha) {
                throw "Could not resolve git SHA for temporary version stamp"
            }
            $projectVersion = "2026.4.0.$shortSha"
            $stamped = $originalVersion.Replace("REPLACE_PROJECT_VERSION", $projectVersion)
            $stamped = $stamped.Replace("REPLACE_BAZEL_BUILD_FLAGS", "--config=$script:BazelConfig")
            [System.IO.File]::WriteAllText($versionPath, $stamped, [System.Text.UTF8Encoding]::new($false))
            $versionWasTemporarilyStamped = $true
            Write-Host "Temporarily stamped src/version.hpp as $projectVersion; source file will be restored after build."
        } else {
            Write-Warning "src/version.hpp is already stamped or locally modified; leaving it unchanged."
        }
    }

    Write-Host ""
    Write-Host "OVMS Windows fast build"
    Write-Host "  mode:              $Mode"
    Write-Host "  bazel config:      $script:BazelConfig"
    Write-Host "  output user root:  $OutputUserRoot"
    Write-Host "  disk cache:        $DiskCache"
    Write-Host "  repository cache:  $RepositoryCache"
    Write-Host "  profiles:          $ProfileDirectory"
    Write-Host "  jobs:              $(if ($Jobs -eq 0) { 'Bazel default' } else { $Jobs })"
    Write-Host "  OpenVINO_DIR:      $OpenVinoDir"
    Write-Host "  OpenCV_DIR:        $OpenCvDir"

    if (-not $SkipFastTests) {
        Invoke-BazelStep "test" "gemma-fast-tests" @(
            "//src/test/llm/generation_config:gemma4_generation_contract_test",
            "//src/test/llm/gemma4_fast:gemma4_parser_contract_test"
        ) @("--test_output=errors", "--test_timeout=600")
    }

    if ($Mode -eq "Dev") {
        Invoke-BazelStep "build" "ovms-dev" @("//src:ovms")
    } else {
        Invoke-BazelStep "build" "ovms-verify" @(
            "//src:ovms",
            "//src:ovms_test",
            "//third_party:espeak_ng",
            "//third_party:espeak_ng_data"
        )
    }

    if ($Mode -eq "Package") {
        Invoke-Package
    }

    $overallWatch.Stop()
    Write-Host ""
    Write-Host "BUILD PASS mode=$Mode elapsed=$($overallWatch.Elapsed)"
    if (-not $NoTranscript) {
        Write-Host "Transcript: $transcriptPath"
    }
} finally {
    if ($versionWasTemporarilyStamped -and $null -ne $originalVersion) {
        [System.IO.File]::WriteAllText($versionPath, $originalVersion, [System.Text.UTF8Encoding]::new($false))
        Write-Host "Restored tracked src/version.hpp after temporary build stamp."
    }
    if (-not $NoTranscript) {
        try { Stop-Transcript | Out-Null } catch {}
    }
}
