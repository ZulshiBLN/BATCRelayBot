#Requires -Version 5.1

function Show-PostRemovalSummary {
    <#
    .SYNOPSIS
    Displays post-removal summary and cleanup instructions (Phase 6).

    .DESCRIPTION
    Shows removal completion status and next steps for user.
    - Confirms successful removal or displays errors
    - Lists manual cleanup steps (VoiceMeeter)
    - Provides next action suggestions
    - Displays removal log location

    .PARAMETER RemovalResult
    Hashtable from Invoke-SecureUninstall with removal status.

    .PARAMETER LogPath
    Path to removal log file.

    .EXAMPLE
    Show-PostRemovalSummary -RemovalResult $result
    #>

    param(
        [hashtable]$RemovalResult = @{},
        [string]$LogPath = ""
    )

    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host "       BATCRelayBot Uninstallation Complete" -ForegroundColor Green
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host ""

    # Removal status
    if ($RemovalResult.Success) {
        Write-Host "Status: " -ForegroundColor Green -NoNewline
        Write-Host "Successfully removed" -ForegroundColor Green
        Write-Host ""
        Write-Host "All BATCRelayBot installation files have been deleted." -ForegroundColor Green
        Write-Host ""
        Write-Host "IMPORTANT - reset your bot token:" -ForegroundColor Yellow
        Write-Host "  config.json was overwritten and deleted, but overwriting a file" -ForegroundColor Gray
        Write-Host "  does not reliably erase it on an SSD. Resetting the token is the" -ForegroundColor Gray
        Write-Host "  only way to be certain it is worthless:" -ForegroundColor Gray
        Write-Host "  https://discord.com/developers/applications > your app > Bot > Reset Token" -ForegroundColor Cyan
    } else {
        Write-Host "Status: " -ForegroundColor Yellow -NoNewline
        Write-Host "Removal completed with issues" -ForegroundColor Yellow
        Write-Host ""

        if ($RemovalResult.Errors -and $RemovalResult.Errors.Count -gt 0) {
            Write-Host "Errors encountered:" -ForegroundColor Yellow
            foreach ($removalError in $RemovalResult.Errors) {
                Write-Host "  * $removalError" -ForegroundColor Yellow
            }
            Write-Host ""
        }
    }

    # Files deleted
    if ($RemovalResult.DeletedFiles -and $RemovalResult.DeletedFiles.Count -gt 0) {
        Write-Host "Removed:" -ForegroundColor Cyan
        foreach ($entry in $RemovalResult.DeletedFiles) {
            Write-Host "  - $entry" -ForegroundColor Gray
        }
    }

    if ($RemovalResult.RemovedDependencies -and $RemovalResult.RemovedDependencies.Count -gt 0) {
        Write-Host ""
        Write-Host "Optional components removed:" -ForegroundColor Cyan
        foreach ($dependency in $RemovalResult.RemovedDependencies) {
            Write-Host "  - $dependency" -ForegroundColor Gray
        }
    }

    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "MANUAL CLEANUP REQUIRED" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "VoiceMeeter (if installed)" -ForegroundColor Yellow
    Write-Host "  VoiceMeeter is a manual installation and was NOT removed." -ForegroundColor Gray
    Write-Host "  To uninstall:" -ForegroundColor Gray
    Write-Host "    1. Open Control Panel" -ForegroundColor Gray
    Write-Host "    2. Go to Programs > Programs and Features" -ForegroundColor Gray
    Write-Host "    3. Find 'VB-Audio VoiceMeeter'" -ForegroundColor Gray
    Write-Host "    4. Click 'Uninstall', then reboot" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Note: Only remove VoiceMeeter if no other applications need it." -ForegroundColor DarkGray
    Write-Host ""

    # Removal log location
    if ($RemovalResult.LogPath -and (Test-Path $RemovalResult.LogPath)) {
        Write-Host "===============================================================" -ForegroundColor Cyan
        Write-Host "REMOVAL LOG" -ForegroundColor Cyan
        Write-Host "===============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "A detailed removal log has been saved for your records:" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  $($RemovalResult.LogPath)" -ForegroundColor White
        Write-Host ""
        Write-Host "This log contains all files that were deleted and any errors encountered." -ForegroundColor Gray
        Write-Host ""
    }

    # Next steps
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "NEXT STEPS" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""

    if ($RemovalResult.Success) {
        Write-Host "BATCRelayBot has been successfully uninstalled." -ForegroundColor Green
        Write-Host ""
        Write-Host "To reinstall in the future:" -ForegroundColor Gray
        Write-Host "  PowerShell> Install-Module -Name BATCRelayBot -Repository PSGallery" -ForegroundColor White
        Write-Host "  PowerShell> Install-BATCRelayBot" -ForegroundColor White
        Write-Host ""
    } else {
        Write-Host "Uninstallation completed with errors (see above)." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To retry or get support:" -ForegroundColor Gray
        Write-Host "  - Check the removal log for details" -ForegroundColor Gray
        Write-Host "  - Review error messages above" -ForegroundColor Gray
        Write-Host "  - Manual deletion may be needed for any remaining files" -ForegroundColor Gray
        Write-Host ""
    }

    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host ""
}

Export-ModuleMember -Function Show-PostRemovalSummary
