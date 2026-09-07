#Requires -Version 5.1

function Uninstall-BATCRelayBot {
    <#
    .SYNOPSIS
    Removes a BATCRelayBot installation.

    .DESCRIPTION
    Five phases:
      1. Inspect the installation
      2. Show what will be removed
      3. Ask about optional components (Python, FFmpeg, PowerShell module)
      4. Final confirmation
      5. Remove, then report what actually happened

    A running bot is stopped automatically, cleanly where possible - it leaves
    the voice channel before exiting.

    Python and FFmpeg are removed only if you confirm each of them; you may be
    using them for other things. VoiceMeeter is never removed: it installs
    audio drivers and needs VB-Audio's own uninstaller.

    .PARAMETER InstallPath
    Installation directory. Defaults to $env:LOCALAPPDATA\BATCRelayBot.

    .PARAMETER Force
    Skip the final confirmation. For unattended cleanup; optional components
    are still only removed when explicitly chosen.

    .EXAMPLE
    Uninstall-BATCRelayBot

    .EXAMPLE
    Uninstall-BATCRelayBot -InstallPath "D:\MyBot"

    .OUTPUTS
    Hashtable with Success, DeletedFiles, RemovedDependencies, Errors, LogPath.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$InstallPath = (Join-Path $env:LOCALAPPDATA "BATCRelayBot"),
        [switch]$Force
    )

    $version = Get-ModuleVersion

    Write-Host ""
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "   BATCRelayBot Uninstaller (v$version)" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host ""

    # ---- Phase 1: inspect ----------------------------------------------
    Write-Host "[1/5] Checking the installation" -ForegroundColor Cyan
    $prerequisites = Confirm-UninstallPrerequisites -BotPath $InstallPath

    foreach ($warning in $prerequisites.Warnings) {
        Write-Host "      Note: $warning" -ForegroundColor Yellow
    }

    if (-not $prerequisites.Valid) {
        Write-Host ""
        foreach ($problem in $prerequisites.Errors) {
            Write-Host "  $problem" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "Nothing was changed." -ForegroundColor Yellow
        Write-Host ""
        return @{ Success = $false; Errors = $prerequisites.Errors }
    }

    Write-Host "      Installation found at $($prerequisites.InstallPath)" -ForegroundColor Green
    Write-Host ""

    # ---- Phase 2: what will go -----------------------------------------
    Write-Host "[2/5] What will be removed" -ForegroundColor Cyan
    Show-RemovalSummary -BotPath $prerequisites.InstallPath | Out-Null

    # ---- Phase 3: optional components ----------------------------------
    Write-Host "[3/5] Optional components" -ForegroundColor Cyan
    $dependencyChoices = Get-DependencyChoices -Prerequisites $prerequisites

    # ---- Phase 4: confirm ----------------------------------------------
    if ($Force) {
        Write-Host "[4/5] Confirmation skipped (-Force)" -ForegroundColor Yellow
        Write-Host ""
    } else {
        Write-Host "[4/5] Confirmation" -ForegroundColor Cyan
        $confirmation = Show-UninstallConfirmation `
            -RemovalPlan @{ InstallPath = $prerequisites.InstallPath } `
            -DependencyChoices $dependencyChoices

        if (-not $confirmation.Confirmed) {
            Write-Host "Nothing was changed." -ForegroundColor Yellow
            Write-Host ""
            return @{ Success = $false; Errors = @("Cancelled by the user") }
        }
    }

    # ---- Phase 5: remove -------------------------------------------------
    Write-Host "[5/5] Removing" -ForegroundColor Cyan
    $removalResult = Invoke-SecureUninstall `
        -BotPath $prerequisites.InstallPath `
        -DependencyChoices $dependencyChoices

    Show-PostRemovalSummary -RemovalResult $removalResult

    return $removalResult
}

Export-ModuleMember -Function Uninstall-BATCRelayBot
