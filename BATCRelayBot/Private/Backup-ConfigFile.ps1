function Backup-ConfigFile {
    <#
    .SYNOPSIS
    Creates timestamped backup of config file, keeps last 10.
    #>

    param(
        [string]$ConfigPath
    )

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$ConfigPath.backup-$timestamp"

    Copy-Item $ConfigPath $backupPath -Force

    $backupDir = Split-Path $ConfigPath
    $backupPattern = "config.json.backup-*"
    $backups = @(Get-ChildItem $backupDir -Filter $backupPattern -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -Skip 10)

    $backups | Remove-Item -Force -ErrorAction SilentlyContinue

    return $backupPath
}
