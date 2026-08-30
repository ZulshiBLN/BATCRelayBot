function Write-ConfigFile {
    <#
    .SYNOPSIS
    Writes JSON content to config file atomically (temp file → replace).
    #>

    param(
        [string]$ConfigPath,
        [string]$JsonContent
    )

    $tempPath = "$ConfigPath.tmp"

    try {
        [System.IO.File]::WriteAllText($tempPath, $JsonContent, [System.Text.Encoding]::UTF8)
        [System.IO.File]::Replace($tempPath, $ConfigPath, $null, $true)
        return $true
    }
    catch {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        throw $_
    }
}
