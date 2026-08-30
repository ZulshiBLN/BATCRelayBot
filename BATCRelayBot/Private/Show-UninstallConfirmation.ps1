#Requires -Version 5.1

function Show-UninstallConfirmation {
    <#
    .SYNOPSIS
    Shows final confirmation screen before uninstallation (Phase 4).

    .DESCRIPTION
    Displays what will be deleted and requires explicit "yes" confirmation.
    Final safety gate before executing destructive operations.
    #>

    param(
        [hashtable]$RemovalPlan = @{},
        [hashtable]$DependencyChoices = @{}
    )

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "       FINAL CONFIRMATION - Removal Cannot Be Undone" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""

    Write-Host "ACTIONS THAT WILL BE PERFORMED:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Installation Removal:" -ForegroundColor Cyan
    Write-Host "  * Delete all BATCRelayBot files" -ForegroundColor Red
    Write-Host "  * Securely delete config.json (3-pass SDelete - UNRECOVERABLE)" -ForegroundColor Red
    Write-Host "  * Delete logs and artifacts" -ForegroundColor Red
    Write-Host "  * Remove installation directory" -ForegroundColor Red
    Write-Host ""

    if ($DependencyChoices.RemovePython -or $DependencyChoices.RemoveFFmpeg -or $DependencyChoices.RemoveModule) {
        Write-Host "Dependency Removal:" -ForegroundColor Cyan
        if ($DependencyChoices.RemovePython) {
            Write-Host "  * Uninstall Python" -ForegroundColor Red
        }
        if ($DependencyChoices.RemoveFFmpeg) {
            Write-Host "  * Uninstall FFmpeg" -ForegroundColor Red
        }
        if ($DependencyChoices.RemoveModule) {
            Write-Host "  * Uninstall PowerShell Module" -ForegroundColor Red
        }
        Write-Host ""
    }

    Write-Host "WARNING:" -ForegroundColor Red
    Write-Host "  * This action CANNOT be undone" -ForegroundColor Red
    Write-Host "  * Discord bot token will be PERMANENTLY DELETED" -ForegroundColor Red
    Write-Host "  * You will need to reinstall if you change your mind" -ForegroundColor Red
    if ($DependencyChoices.RemovePython -or $DependencyChoices.RemoveFFmpeg) {
        Write-Host "  * Uninstalling Python/FFmpeg may break other applications" -ForegroundColor Red
    }
    Write-Host "  * VoiceMeeter is NOT removed (use vendor uninstaller)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host ""

    Write-Host "Type 'yes' to proceed with uninstallation, or anything else to cancel:" -ForegroundColor Cyan
    Write-Host ""

    try {
        $response = Read-Host "Confirm uninstallation"
    } catch {
        Write-Host "(No input available - cancelling)" -ForegroundColor Yellow
        $response = "no"
    }

    $confirmed = ($response -eq "yes")

    if ($confirmed) {
        Write-Host ""
        Write-Host "Ok Uninstallation confirmed. Proceeding..." -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host ""
        Write-Host "Uninstallation cancelled." -ForegroundColor Yellow
        Write-Host ""
    }

    return @{
        Confirmed = $confirmed
        ConfirmationTime = Get-Date
    }
}

Export-ModuleMember -Function Show-UninstallConfirmation