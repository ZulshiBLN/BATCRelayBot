#Requires -Version 5.1

function Install-BATCRelayBot {
    <#
    .SYNOPSIS
    Installs BATCRelayBot with 6-phase industry-standard installer flow.

    .DESCRIPTION
    Guides user through complete installation with:
    - Phase 1: Silently detect all prerequisites
    - Phase 2: Display prerequisite status
    - Phase 3: Collect Discord configuration
    - Phase 4: Review selections before install
    - Phase 5: Execute installation
    - Phase 6: Display success and next steps

    No admin rights required.

    .PARAMETER BotPath
    Installation path for bot files.
    Defaults to $env:USERPROFILE\AppData\Local\BATCRelayBot

    .EXAMPLE
    Install-BATCRelayBot

    .EXAMPLE
    Install-BATCRelayBot -BotPath "D:\MyBot"
    #>

    param(
        [string]$BotPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
    )

    $ErrorActionPreference = "Stop"

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   BATCRelayBot Installation (v1.3.16)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    try {
        # PHASE 1: Silent prerequisites detection
        Write-Host "[Phase 1] Detecting prerequisites..." -ForegroundColor Gray
        $prerequisites = @{
            Python = Find-Python
            FFmpeg = Find-FFmpeg
            VoiceMeeter = Find-VoiceMeeter
            BeyondATC = Find-BeyondATC
        }
        Write-Host "Prerequisites detected" -ForegroundColor Green
        Write-Host ""

        # PHASE 2: Display info screen
        Write-Host "[Phase 2] Prerequisite Status" -ForegroundColor Gray
        Show-PrerequisitesInfo
        Write-Host ""

        # PHASE 3: Collect Discord configuration
        Write-Host "[Phase 3] Discord Configuration" -ForegroundColor Gray
        $discordConfig = Get-DiscordConfiguration
        if (-not $discordConfig) {
            Write-Host "ERROR: Could not collect Discord configuration" -ForegroundColor Red
            exit 1
        }
        Write-Host ""

        # PHASE 4b: Auto-install confirmation (if prerequisites missing) - BEFORE summary check
        $missingTools = @()
        if (-not $prerequisites.Python.Found) { $missingTools += "Python 3.12" }
        if (-not $prerequisites.FFmpeg.Found) { $missingTools += "FFmpeg" }

        if ($missingTools.Count -gt 0) {
            Write-Host "[Phase 4b] Auto-Install Missing Tools" -ForegroundColor Gray
            Write-Host "The following tools are missing: $($missingTools -join ', ')" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Options:" -ForegroundColor Gray
            Write-Host "  [1] Auto-install missing tools (recommended)" -ForegroundColor Gray
            Write-Host "  [2] Continue without auto-install" -ForegroundColor Gray
            Write-Host "  [3] Show manual installation instructions" -ForegroundColor Gray
            Write-Host ""

            $autoInstallChoice = Read-Host "Select option (1/2/3)"

            if ($autoInstallChoice -eq "1") {
                Write-Host ""
                Write-Host "Auto-installing missing tools..." -ForegroundColor Cyan
                Invoke-AutoInstallPrerequisites -Prerequisites $prerequisites
                Write-Host ""
            } elseif ($autoInstallChoice -eq "3") {
                Write-Host ""
                Write-Host "Manual Installation Instructions:" -ForegroundColor Cyan
                if ($missingTools -contains "Python 3.12") {
                    Write-Host "  Python 3.12: https://www.python.org/downloads/" -ForegroundColor Gray
                }
                if ($missingTools -contains "FFmpeg") {
                    Write-Host "  FFmpeg: https://ffmpeg.org/download.html" -ForegroundColor Gray
                }
                Write-Host ""
                Write-Host "After installation, please re-run this installer" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Press Enter to exit..." -ForegroundColor Yellow
                Read-Host
                exit 0
            }
            Write-Host ""
        }

        # PHASE 4: Display summary before installing
        Write-Host "[Phase 4] Installation Summary" -ForegroundColor Gray
        $summary = Show-InstallationSummary -Prerequisites $prerequisites -DiscordConfig $discordConfig

        if (-not $summary.CanProceed) {
            Write-Host ""
            Write-Host "Installation cannot proceed. Check requirements above." -ForegroundColor Red
            Write-Host "Press Enter to exit..." -ForegroundColor Yellow
            Read-Host
            exit 1
        }

        Write-Host ""

        # PHASE 5: Execute installation
        Write-Host "[Phase 5] Installing..." -ForegroundColor Gray
        $installResult = Start-Installation -Prerequisites $prerequisites -DiscordConfig $discordConfig

        if (-not $installResult.Success) {
            Write-Host ""
            Write-Host "Installation failed: $($installResult.Error)" -ForegroundColor Red
            Write-Host ""
            Write-Host "Press Enter to exit..." -ForegroundColor Yellow
            Read-Host
            exit 1
        }

        # PHASE 6: Success message and next steps
        Write-Host "[Phase 6] Installation Complete" -ForegroundColor Gray
        Show-PostInstallationMessage `
            -InstallPath $installResult.InstallPath `
            -ConfigPath $installResult.ConfigPath `
            -LogPath $installResult.LogPath

        Write-Host ""
        Write-Host "Installation finished successfully!" -ForegroundColor Green
        Write-Host "Log file: $($installResult.LogPath)" -ForegroundColor Gray

    } catch {
        Write-Host ""
        Write-Host "ERROR: Installation failed" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""
        Write-Host "For troubleshooting, check the installation log." -ForegroundColor Yellow

        if ($installResult.LogPath) {
            Write-Host "Log: $($installResult.LogPath)" -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "Press Enter to exit..." -ForegroundColor Yellow
        Read-Host
        exit 1
    }

    Write-Host ""
}

function Invoke-AutoInstallPrerequisites {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Prerequisites
    )

    if (-not $Prerequisites.Python.Found) {
        Write-Host "  Installing Python 3.12..." -ForegroundColor Gray
        winget install Python.Python.3.12 --silent 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','User')
            Start-Sleep -Seconds 1
            Write-Host "  ✓ Python installed" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Python installation failed" -ForegroundColor Yellow
        }
    }

    if (-not $Prerequisites.FFmpeg.Found) {
        Write-Host "  Installing FFmpeg..." -ForegroundColor Gray
        winget install Gyan.FFmpeg --silent 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','User')
            Start-Sleep -Seconds 1
            Write-Host "  ✓ FFmpeg installed" -ForegroundColor Green
        } else {
            Write-Host "  ✗ FFmpeg installation failed" -ForegroundColor Yellow
        }
    }
}

Export-ModuleMember -Function Install-BATCRelayBot