function Write-ConfigFile {
    <#
    .SYNOPSIS
    Writes JSON content to config file (temp file write → atomic replace).
    #>

    param(
        [string]$ConfigPath,
        [string]$JsonContent
    )

    $tempPath = "$ConfigPath.tmp"

    try {
        [System.IO.File]::WriteAllText($tempPath, $JsonContent, [System.Text.Encoding]::UTF8)
        Move-Item $tempPath $ConfigPath -Force
        return $true
    }
    catch {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        throw $_
    }
}
