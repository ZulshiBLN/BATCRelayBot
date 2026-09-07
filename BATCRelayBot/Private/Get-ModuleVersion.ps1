#Requires -Version 5.1

function Get-ModuleVersion {
    <#
    .SYNOPSIS
    Returns the module version as a string.

    .DESCRIPTION
    (Get-Module BATCRelayBot).Version reports 0.0 when the .psm1 was imported
    directly instead of through its manifest - which is how the module is
    loaded during development and in the test suite. Falling back to the
    manifest keeps the banner, the log header and the Discord User-Agent
    honest in both cases.
    #>
    [OutputType([string])]
    param()

    try {
        $module = Get-Module BATCRelayBot
        if ($module -and $module.Version -and $module.Version.ToString() -ne '0.0') {
            return $module.Version.ToString()
        }

        $manifestPath = $null
        if ($module -and $module.ModuleBase) {
            $manifestPath = Join-Path $module.ModuleBase "BATCRelayBot.psd1"
        }
        if (-not $manifestPath -or -not (Test-Path $manifestPath)) {
            $manifestPath = Join-Path $PSScriptRoot "..\BATCRelayBot.psd1"
        }

        if (Test-Path $manifestPath) {
            $manifest = Import-PowerShellDataFile -Path $manifestPath -ErrorAction Stop
            if ($manifest.ModuleVersion) { return $manifest.ModuleVersion }
        }
    } catch {
        # Fall through to the placeholder below.
    }

    return "unknown"
}

Export-ModuleMember -Function 'Get-ModuleVersion'
