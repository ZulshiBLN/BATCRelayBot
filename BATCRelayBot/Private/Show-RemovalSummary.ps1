#Requires -Version 5.1

function Show-RemovalSummary {
    <#
    .SYNOPSIS
    Displays what will be deleted during uninstallation (Phase 2).

    .DESCRIPTION
    Shows a formatted, read-only summary of files that will be removed.
    No prompts - purely informational. Highlights sensitive data (Discord token).

    .PARAMETER BotPath
    Installation directory path.

    .PARAMETER PrerequisiteStatus
    Hashtable from Phase 1 (Confirm-UninstallPrerequisites).

    .EXAMPLE
    Show-RemovalSummary -BotPath "C:\Users\...\AppData\Local\BATCRelayBot"
    #>

    param(
        [string]$BotPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot",
        [hashtable]$PrerequisiteStatus = @{}
    )

    # Calculate total disk space
    $totalSize = 0
    if (Test-Path $BotPath) {
        $totalSize = (Get-ChildItem -Path $BotPath -Recurse -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum).Sum
    }
    $sizeGB = [math]::Round($totalSize / 1GB, 2)
    $sizeMB = [math]::Round($totalSize / 1MB, 2)

    # Build file list
    $files = @()
    if (Test-Path $BotPath) {
        $files = @(Get-ChildItem -Path $BotPath -Recurse -ErrorAction SilentlyContinue |
                   Select-Object -ExpandProperty Name)
    }

    # Display banner
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "        BATCRelayBot Removal - What Will Be Deleted?" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    # Installation Location
    Write-Host "Installation Location:" -ForegroundColor Yellow
    Write-Host "  Path: $BotPath" -ForegroundColor Gray
    Write-Host ""

    # Files to delete
    Write-Host "Files to be DELETED:" -ForegroundColor Yellow
    if ($files.Count -gt 0) {
        $files | Sort-Object | ForEach-Object {
            Write-Host "  • $_" -ForegroundColor Gray
        }
    } else {
        Write-Host "  (No files found)" -ForegroundColor Gray
    }
    Write-Host ""

    # Sensitive data warning
    Write-Host "Configuration & Sensitive Data:" -ForegroundColor Yellow
    $configPath = Join-Path $BotPath "config.json"
    if (Test-Path $configPath) {
        Write-Host "  ⚠ config.json (CONTAINS DISCORD TOKEN - SECURELY DELETED)" -ForegroundColor Red
        Write-Host "    Deletion Method: 3-pass SDelete overwrite (unrecoverable)" -ForegroundColor DarkRed
    } else {
        Write-Host "  config.json (not found)" -ForegroundColor Gray
    }
    Write-Host ""

    # Logs & artifacts
    Write-Host "Logs & Artifacts:" -ForegroundColor Yellow
    $logFiles = @(Get-ChildItem -Path $BotPath -Filter "*.log" -ErrorAction SilentlyContinue |
                  Select-Object -ExpandProperty Name)
    if ($logFiles.Count -gt 0) {
        $logFiles | ForEach-Object {
            Write-Host "  • $_" -ForegroundColor Gray
        }
    } else {
        Write-Host "  (No log files found)" -ForegroundColor Gray
    }
    Write-Host ""

    # Installation directory
    Write-Host "Installation Directory:" -ForegroundColor Yellow
    Write-Host "  Complete directory will be removed" -ForegroundColor Gray
    Write-Host "  Path: $BotPath" -ForegroundColor Gray
    Write-Host ""

    # Disk space
    Write-Host "Disk Space Freed:" -ForegroundColor Yellow
    if ($totalSize -gt 0) {
        if ($sizeGB -gt 0) {
            Write-Host "  Approximately: $sizeGB GB" -ForegroundColor Green
        } else {
            Write-Host "  Approximately: $sizeMB MB" -ForegroundColor Green
        }
    } else {
        Write-Host "  (No data to calculate)" -ForegroundColor Gray
    }
    Write-Host ""

    # Manual steps
    Write-Host "Manual Steps After Removal:" -ForegroundColor Yellow
    Write-Host "  1. If you installed VoiceMeeter: Use Windows Control Panel → Programs" -ForegroundColor Gray
    Write-Host "     to uninstall it separately (we don't touch it)" -ForegroundColor Gray
    Write-Host "  2. Python & FFmpeg: Only removed if you choose in next screen" -ForegroundColor Gray
    Write-Host "  3. PowerShell Module: Only removed if you choose in next screen" -ForegroundColor Gray
    Write-Host ""

    # Footer
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    return $true
}

Export-ModuleMember -Function Show-RemovalSummary
