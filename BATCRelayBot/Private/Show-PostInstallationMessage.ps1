#Requires -Version 5.1

function Show-PostInstallationMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host "           INSTALLATION SUCCESSFUL!" -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host "========================================================" -ForegroundColor Green -BackgroundColor DarkGreen
    Write-Host ""

    Write-Host "Installation Complete" -ForegroundColor Green
    Write-Host "=====================" -ForegroundColor Green
    Write-Host ""
    Write-Host "BATCRelayBot has been installed successfully!" -ForegroundColor White
    Write-Host ""

    Write-Host "Installation Details:" -ForegroundColor Cyan
    Write-Host "=====================" -ForegroundColor Cyan
    Write-Host "  Installation Path: $InstallPath" -ForegroundColor Gray
    Write-Host "  Configuration File: $ConfigPath" -ForegroundColor Gray
    Write-Host "  Installation Log: $LogPath" -ForegroundColor Gray
    Write-Host ""

    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "===========" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. VERIFY INSTALLATION" -ForegroundColor Cyan
    Write-Host "   Check the installation log for any warnings:" -ForegroundColor Gray
    Write-Host "   View-Content '$LogPath'" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "2. START THE BOT" -ForegroundColor Cyan
    Write-Host "   Run the bot with:" -ForegroundColor Gray
    Write-Host "   python '$InstallPath\bot.py'" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "3. VERIFY BOT CONNECTION" -ForegroundColor Cyan
    Write-Host "   The bot will connect to your Discord server" -ForegroundColor Gray
    Write-Host "   Check the Discord channel for a connection message" -ForegroundColor Gray
    Write-Host ""

    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "================" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "If you encounter issues:" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Problem: Bot won't start" -ForegroundColor Red
    Write-Host "  Solution: Check Python is installed" -ForegroundColor Yellow
    Write-Host "  python --version" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  Problem: Bot connects then disconnects" -ForegroundColor Red
    Write-Host "  Solution: Verify Discord token in config.json" -ForegroundColor Yellow
    Write-Host "  Check file: $ConfigPath" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  Problem: No audio is captured" -ForegroundColor Red
    Write-Host "  Solution: Verify VoiceMeeter is installed and configured" -ForegroundColor Yellow
    Write-Host "  Download: https://vb-audio.com/Voicemeeter/" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  Problem: Missing Python dependencies" -ForegroundColor Red
    Write-Host "  Solution: Install dependencies manually" -ForegroundColor Yellow
    Write-Host "  pip install -r requirements.txt" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "Documentation & Support:" -ForegroundColor Yellow
    Write-Host "========================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  README: Installation guide and usage" -ForegroundColor Gray
    Write-Host "  Discord Bot Setup: https://discord.com/developers/applications" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Installation Log: Contains detailed setup information" -ForegroundColor Gray
    Write-Host "  Location: $LogPath" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "What's Next:" -ForegroundColor Cyan
    Write-Host "============" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. Start the bot and verify it connects" -ForegroundColor Gray
    Write-Host "  2. Test audio streaming from your flight sim to Discord" -ForegroundColor Gray
    Write-Host "  3. Configure optional features (BeyondATC, etc.)" -ForegroundColor Gray
    Write-Host "  4. Set up automated bot restart if desired" -ForegroundColor Gray
    Write-Host ""

    Write-Host "========================================================" -ForegroundColor Green
    Write-Host "      Thank you for using BATCRelayBot!" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host ""

    return @{
        InstallPath = $InstallPath
        ConfigPath = $ConfigPath
        LogPath = $LogPath
        Success = $true
    }
}

Export-ModuleMember -Function Show-PostInstallationMessage
