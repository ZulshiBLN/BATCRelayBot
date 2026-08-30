#Requires -Version 5.1

function Uninstall-BATCRelayBot {
    <#
    .SYNOPSIS
    Uninstalls BATCRelayBot with secure file deletion.

    .DESCRIPTION
    Complete uninstallation of BATCRelayBot following a 6-phase workflow:
    1. Pre-checks (installation directory exists, bot not running)
    2. Summary (files to be deleted, disk space)
    3. Optional dependencies (Python, FFmpeg, module)
    4. Final confirmation (requires explicit "yes")
    5. Secure deletion (config.json + all files)
    6. Post-removal summary (next steps, manual cleanup)

    Securely deletes Discord bot token via SDelete 3-pass overwrite.
    VoiceMeeter must be removed manually (vendor software).

    .PARAMETER InstallPath
    Installation directory (default: $env:USERPROFILE\AppData\Local\BATCRelayBot)

    .EXAMPLE
    Uninstall-BATCRelayBot
    Uninstall-BATCRelayBot -InstallPath "C:\Custom\BATCRelayBot"

    .NOTES
    This function requires manual confirmation before deletion.
    All data will be permanently removed - no recovery possible.
    #>

    param(
        [string]$InstallPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
    )

    Write-Host ""
    Write-Host "BATCRelayBot Uninstaller" -ForegroundColor Cyan
    Write-Host "Version 1.0" -ForegroundColor Gray
    Write-Host ""

    # Phase 1: Pre-checks
    Write-Host "Phase 1: Checking prerequisites..." -ForegroundColor Cyan
    $prerequisites = Confirm-UninstallPrerequisites -InstallPath $InstallPath

    if (-not $prerequisites.Valid) {
        Write-Host ""
        Write-Host "Uninstallation aborted." -ForegroundColor Yellow
        Write-Host ""
        if ($prerequisites.Errors -and $prerequisites.Errors.Count -gt 0) {
            foreach ($error in $prerequisites.Errors) {
                Write-Host "  * $error" -ForegroundColor Yellow
            }
        }
        return
    }

    Write-Host "OK - Installation found and valid" -ForegroundColor Green
    Write-Host ""

    # Phase 2: Show removal summary
    Write-Host "Phase 2: Removal Summary" -ForegroundColor Cyan
    $removalSummary = Show-RemovalSummary -InstallPath $prerequisites.InstallPath

    if (-not $removalSummary.Ready) {
        Write-Host ""
        Write-Host "Uninstallation aborted." -ForegroundColor Yellow
        return
    }

    # Phase 3: Get optional dependency choices
    Write-Host ""
    Write-Host "Phase 3: Optional Dependencies" -ForegroundColor Cyan
    $dependencyChoices = Get-DependencyChoices -Prerequisites $prerequisites

    # Phase 4: Final confirmation
    Write-Host ""
    Write-Host "Phase 4: Final Confirmation" -ForegroundColor Cyan
    $confirmation = Show-UninstallConfirmation -RemovalPlan $removalSummary -DependencyChoices $dependencyChoices

    if (-not $confirmation.Confirmed) {
        Write-Host ""
        Write-Host "Uninstallation cancelled." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # Phase 5: Secure removal
    Write-Host ""
    Write-Host "Phase 5: Secure Removal" -ForegroundColor Cyan
    $removalResult = Invoke-SecureUninstall -BotPath $prerequisites.InstallPath -DependencyChoices $dependencyChoices

    # Phase 6: Post-removal summary
    Write-Host ""
    Write-Host "Phase 6: Summary" -ForegroundColor Cyan
    Show-PostRemovalSummary -RemovalResult $removalResult

    Write-Host ""
}

Export-ModuleMember -Function Uninstall-BATCRelayBot
