function Backup-ConfigFile {
    <#
    .SYNOPSIS
    Creates timestamped backup of config file, keeps last 10.

    .DESCRIPTION
    Creates a backup of the configuration file with timestamp in format YYYYMMDD-HHmmss.
    Automatically removes old backups, keeping only the 10 most recent.

    .PARAMETER ConfigPath
    Full path to config.json file to backup.

    .OUTPUTS
    [string] Path to created backup file (e.g., config.json.backup-20260830-143022)

    .EXAMPLE
    $backup = Backup-ConfigFile -ConfigPath 'C:\BATCRelayBot\config.json'
    Write-Host "Backup created: $backup"

    .NOTES
    - Backup format: [filename].backup-YYYYMMDD-HHmmss
    - Retention policy: Keeps last 10 backups (older ones auto-deleted)
    - Cleanup: Happens automatically after new backup created
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
