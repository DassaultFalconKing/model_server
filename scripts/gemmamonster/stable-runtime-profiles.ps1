Set-StrictMode -Version Latest

$script:GemmamonsterStableRuntimeProfiles = [ordered]@{
    'maintainer-rc2' = [ordered]@{
        label = 'OpenVINO Model Server latest maintainer 2026.4 RC2 runtime line'
        OV_SOURCE_BRANCH = '227c33757d1ef95d4da506d00686f923fdd2a535'
        OV_TOKENIZERS_BRANCH = 'a04accf6282d9b304214b492694b18c3979f667a'
        OV_GENAI_BRANCH = '7ea2546852a382cd16bd22dea0cfad2db70ed744'
        GENAI_PACKAGE_URL_WINDOWS = 'https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/pre-release/2026.4.0.0rc2/openvino_genai_windows_2026.4.0.0rc2_x86_64.zip'
        package_marker = '2026.4.0.0rc2'
        default_short_root = 'g54r2'
    }
    'known-good-rc1' = [ordered]@{
        label = 'GEMMAMONSTER previously accepted 2026.4 RC1 runtime line'
        OV_SOURCE_BRANCH = '61afcb26271140347709138b13d678e8b1b5925c'
        OV_TOKENIZERS_BRANCH = 'a04accf6282d9b304214b492694b18c3979f667a'
        OV_GENAI_BRANCH = '5f7f1278107d7eae3990ce906bbcfcb69ac3397f'
        GENAI_PACKAGE_URL_WINDOWS = 'https://storage.openvinotoolkit.org/repositories/openvino_genai/packages/pre-release/2026.4.0.0rc1/openvino_genai_windows_2026.4.0.0rc1_x86_64.zip'
        package_marker = '2026.4.0.0rc1'
        default_short_root = 'g54r1'
    }
}

function Get-GemmamonsterStableRuntimeProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('maintainer-rc2','known-good-rc1')]
        [string]$Name
    )

    $profile = $script:GemmamonsterStableRuntimeProfiles[$Name]
    if ($null -eq $profile) { throw "Unknown GEMMAMONSTER stable runtime profile: $Name" }
    return $profile
}
