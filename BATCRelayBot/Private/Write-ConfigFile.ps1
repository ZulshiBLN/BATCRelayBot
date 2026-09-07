function Write-ConfigFile {
    <#
    .SYNOPSIS
    Writes JSON content to config file (temp file write -> atomic replace).

    .DESCRIPTION
    Safely writes JSON content to config file using temp file + Move-Item pattern.
    This provides atomic operation: either entire write succeeds or entire write fails.
    Prevents partial/corrupted config files.

    .PARAMETER ConfigPath
    Full path to target config.json file.

    .PARAMETER JsonContent
    JSON string content to write (should be valid JSON).

    .OUTPUTS
    [bool] $true if write succeeded, throws exception on failure

    .EXAMPLE
    $json = '{\"token\":\"xyz\",\"channel_id\":\"123456789012345678\"}'
    Write-ConfigFile -ConfigPath 'C:\BATCRelayBot\config.json' -JsonContent $json

    .NOTES
    - Uses temp file: creates [path].tmp, then moves to target (atomic on Windows)
    - Encoding: UTF-8 without BOM
    - Cleanup: Temp file auto-removed on success or error
    - Rollback: On exception, config file remains unchanged
    #>

    param(
        [string]$ConfigPath,
        [string]$JsonContent
    )

    $tempPath = "$ConfigPath.tmp"

    try {
        # UTF8Encoding($false) - [System.Text.Encoding]::UTF8 emits a BOM, which
        # contradicts the documented behaviour above and trips strict readers.
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempPath, $JsonContent, $utf8NoBom)
        Move-Item $tempPath $ConfigPath -Force
        return $true
    }
    catch {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        throw $_
    }
}

Export-ModuleMember -Function Write-ConfigFile
