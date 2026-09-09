#Requires -Version 5.1

function Show-UninstallConfirmation {
    <#
    .SYNOPSIS
    The last gate before anything is deleted (uninstaller phase 4).

    .DESCRIPTION
    Two things here used to be untrue rather than merely long.

    "Dependency Removal" listed whatever the choices hashtable contained rather
    than what the user had approved, and the warning that removing Python or
    FFmpeg can break other applications appeared whether or not either had been
    chosen. A warning that fires when nothing is at stake teaches people to read
    past it.

    The confirmation word is "uninstall" rather than "yes". Typing nine
    considered characters is a different act from typing three reflexive ones,
    and this is the point where a mistake cannot be taken back.
    #>
    [OutputType([hashtable])]
    param(
        [hashtable]$RemovalPlan = @{},
        [hashtable]$DependencyChoices = @{}
    )

    $approved = @()
    if ($DependencyChoices.RemovePython) { $approved += "Python" }
    if ($DependencyChoices.RemoveFFmpeg) { $approved += "FFmpeg" }

    Write-Host ""
    Write-Host "        This cannot be undone." -ForegroundColor Red
    Write-Host ""
    Write-Host "        Will be removed:" -ForegroundColor Yellow
    Write-Host "          the installed files, including config.json with your bot token" -ForegroundColor Gray

    Write-Host ""
    if ($approved.Count -gt 0) {
        Write-Host "        Optional components: $($approved -join ' and ')" -ForegroundColor Yellow
        Write-Host "          removing $(if ($approved.Count -eq 1) { 'it' } else { 'them' }) can break other software that uses $(if ($approved.Count -eq 1) { 'it' } else { 'them' })" -ForegroundColor Yellow
    } else {
        Write-Host "        Optional components: None" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "        VoiceMeeter and BeyondATC are NOT removed - both need their" -ForegroundColor Yellow
    Write-Host "        vendor's own uninstaller." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "        Reset your bot token afterwards: overwriting a file on an SSD" -ForegroundColor Yellow
    Write-Host "        does not reliably erase it." -ForegroundColor Yellow
    Write-Host ""

    try {
        $response = Read-Host "        Type 'uninstall' to proceed, anything else to cancel"
    } catch {
        Write-Host "        (no input available - cancelling)" -ForegroundColor Yellow
        $response = ""
    }

    $confirmed = ("$response".Trim() -eq "uninstall")

    Write-Host ""
    if (-not $confirmed) {
        Write-Host "        Cancelled." -ForegroundColor Yellow
        Write-Host ""
    }

    return @{
        Confirmed        = $confirmed
        ConfirmationTime = Get-Date
    }
}

Export-ModuleMember -Function Show-UninstallConfirmation
