#Requires -Version 5.1

function Get-DependencyChoices {
    <#
    .SYNOPSIS
    Prompts user for optional dependency removal choices (Phase 3).

    .DESCRIPTION
    Detects WinGet-installed dependencies and asks user which ones to remove.
    Only shows prompts for WinGet-installed packages (Python, FFmpeg, PowerShell module).
    VoiceMeeter is NOT included (manual uninstall via vendor).

    .PARAMETER Prerequisites
    Hashtable from Phase 1 (optional, for reference).

    .OUTPUTS
    Hashtable with user choices:
    @{
        RemovePython = $true/$false
        RemoveFFmpeg = $true/$false
        RemoveModule = $true/$false
        SkipDependencyPrompts = $true/$false  # If WinGet unavailable
    }

    .EXAMPLE
    $choices = Get-DependencyChoices
    if ($choices.RemovePython) { winget uninstall Python }
    #>

    param(
        [hashtable]$Prerequisites = @{}
    )

    $choices = @{
        RemovePython = $false
        RemoveFFmpeg = $false
        RemoveModule = $false
        SkipDependencyPrompts = $false
    }

    Write-Host ""
    Write-Host "Optional Dependency Removal" -ForegroundColor Yellow
    Write-Host "=======================================" -ForegroundColor Yellow
    Write-Host ""

    # Check if WinGet is available
    $wingetAvailable = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)

    if (-not $wingetAvailable) {
        Write-Host "⚠ WinGet not found. Skipping optional dependency detection." -ForegroundColor Yellow
        Write-Host ""
        $choices.SkipDependencyPrompts = $true
        return $choices
    }

    # Detect Python (any version 3.x)
    Write-Host "1. Python" -ForegroundColor Cyan
    $pythonList = winget list "Python" 2>$null | Select-String "Python\."

    if ($pythonList) {
        # Extract version info
        $pythonString = $pythonList | Out-String
        if ($pythonString -match "Python\.Python\.(\d+\.\d+)") {
            $pythonVersion = $matches[1]
            Write-Host "   Found: Python $pythonVersion (installed via WinGet)" -ForegroundColor Gray
        } else {
            Write-Host "   Found: Python (installed via WinGet)" -ForegroundColor Gray
        }

        Write-Host "   ⚠ Warning: Other programs may depend on Python" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   Uninstall Python?"
        try {
            $pythonChoice = Read-Host "   (Yes/No/Info)"
        } catch {
            Write-Host "   (No input available - defaulting to No)" -ForegroundColor Gray
            $pythonChoice = "No"
        }

        switch ($pythonChoice.ToLower()) {
            "yes" { $choices.RemovePython = $true }
            "info" {
                Write-Host ""
                Write-Host "   Python is required for many development tools." -ForegroundColor Gray
                Write-Host "   Uninstalling may break other applications." -ForegroundColor Gray
                Write-Host "   Only remove if you're sure nothing else needs it." -ForegroundColor Gray
                Write-Host ""
                try {
                    $pythonRetry = Read-Host "   Uninstall Python anyway? (Yes/No)"
                } catch {
                    $pythonRetry = "No"
                }
                if ($pythonRetry.ToLower() -eq "yes") { $choices.RemovePython = $true }
            }
            default { $choices.RemovePython = $false }
        }
    } else {
        Write-Host "   Not installed (or not via WinGet)" -ForegroundColor Gray
    }
    Write-Host ""

    # Detect FFmpeg (Gyan.FFmpeg)
    Write-Host "2. FFmpeg" -ForegroundColor Cyan
    $ffmpegFound = $null -ne (winget show --id Gyan.FFmpeg 2>$null)

    if ($ffmpegFound) {
        Write-Host "   Found: FFmpeg (installed via WinGet)" -ForegroundColor Gray
        Write-Host "   ⚠ Warning: Used by media applications and tools" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   Uninstall FFmpeg?"
        try {
            $ffmpegChoice = Read-Host "   (Yes/No/Info)"
        } catch {
            Write-Host "   (No input available - defaulting to No)" -ForegroundColor Gray
            $ffmpegChoice = "No"
        }

        switch ($ffmpegChoice.ToLower()) {
            "yes" { $choices.RemoveFFmpeg = $true }
            "info" {
                Write-Host ""
                Write-Host "   FFmpeg is used by video/audio applications." -ForegroundColor Gray
                Write-Host "   Uninstalling may break streaming and media tools." -ForegroundColor Gray
                Write-Host "   Only remove if you're sure nothing else needs it." -ForegroundColor Gray
                Write-Host ""
                try {
                    $ffmpegRetry = Read-Host "   Uninstall FFmpeg anyway? (Yes/No)"
                } catch {
                    $ffmpegRetry = "No"
                }
                if ($ffmpegRetry.ToLower() -eq "yes") { $choices.RemoveFFmpeg = $true }
            }
            default { $choices.RemoveFFmpeg = $false }
        }
    } else {
        Write-Host "   Not installed (or not via WinGet)" -ForegroundColor Gray
    }
    Write-Host ""

    # PowerShell Module
    Write-Host "3. PowerShell Module (BATCRelayBot)" -ForegroundColor Cyan
    $moduleInstalled = $null -ne (Get-Module BATCRelayBot -ErrorAction SilentlyContinue) -or `
                      $null -ne (Get-Module -ListAvailable -Name BATCRelayBot -ErrorAction SilentlyContinue)

    if ($moduleInstalled) {
        Write-Host "   Found: BATCRelayBot PowerShell Module" -ForegroundColor Gray
        Write-Host ""
        Write-Host "   Uninstall PowerShell Module?"
        try {
            $moduleChoice = Read-Host "   (Yes/No)"
        } catch {
            Write-Host "   (No input available - defaulting to No)" -ForegroundColor Gray
            $moduleChoice = "No"
        }

        switch ($moduleChoice.ToLower()) {
            "yes" { $choices.RemoveModule = $true }
            default { $choices.RemoveModule = $false }
        }
    } else {
        Write-Host "   Not installed as PowerShell module" -ForegroundColor Gray
    }
    Write-Host ""

    # VoiceMeeter Note (NOT included in this phase)
    Write-Host "Note: VoiceMeeter (if installed)" -ForegroundColor Gray
    Write-Host "  VoiceMeeter is a manual installation and must be uninstalled" -ForegroundColor Gray
    Write-Host "  using the vendor's uninstaller (Control Panel → Programs)" -ForegroundColor Gray
    Write-Host ""

    # Summary
    Write-Host "=======================================" -ForegroundColor Yellow
    Write-Host ""

    return $choices
}

Export-ModuleMember -Function Get-DependencyChoices
