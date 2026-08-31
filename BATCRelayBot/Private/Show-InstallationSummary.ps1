#Requires -Version 5.1

function Show-InstallationSummary {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Prerequisites,
        [Parameter(Mandatory = $true)]
        [hashtable]$DiscordConfig
    )

    Write-Host ""
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host "   Installation Summary - Review Before Proceed   " -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host ""

    # Prerequisites Section
    Write-Host "Prerequisites Status:" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ""
    Write-Host "  Python Installation:" -ForegroundColor Gray
    if ($Prerequisites.Python.Found) {
        Write-Host "    Path: $($Prerequisites.Python.Path)" -ForegroundColor Green
        Write-Host "    Version: $($Prerequisites.Python.Version)" -ForegroundColor Green
    } else {
        Write-Host "    Status: NOT FOUND" -ForegroundColor Red
    }
    Write-Host ""

    Write-Host "  FFmpeg Installation:" -ForegroundColor Gray
    if ($Prerequisites.FFmpeg.Found) {
        Write-Host "    Path: $($Prerequisites.FFmpeg.Path)" -ForegroundColor Green
    } else {
        Write-Host "    Status: NOT FOUND" -ForegroundColor Red
    }
    Write-Host ""

    Write-Host "  VoiceMeeter Installation:" -ForegroundColor Gray
    if ($Prerequisites.VoiceMeeter.Found) {
        Write-Host "    Path: $($Prerequisites.VoiceMeeter.Path)" -ForegroundColor Green
    } else {
        Write-Host "    Status: NOT FOUND (Required)" -ForegroundColor Red
    }
    Write-Host ""

    Write-Host "  BeyondATC Installation:" -ForegroundColor Gray
    if ($Prerequisites.BeyondATC.Found) {
        Write-Host "    Status: INSTALLED (optional)" -ForegroundColor Green
    } else {
        Write-Host "    Status: NOT INSTALLED (optional, can skip)" -ForegroundColor Gray
    }
    Write-Host ""

    # Discord Configuration Section
    Write-Host "Discord Configuration:" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ""
    Write-Host "  Bot Token:" -ForegroundColor Gray
    if ($DiscordConfig.BotToken) {
        Write-Host "    Token: [REDACTED] (length: $($DiscordConfig.BotToken.Length) chars)" -ForegroundColor Green
    } else {
        Write-Host "    Token: NOT PROVIDED" -ForegroundColor Red
    }
    Write-Host ""

    Write-Host "  Server ID:" -ForegroundColor Gray
    if ($DiscordConfig.ServerId) {
        Write-Host "    ID: $($DiscordConfig.ServerId)" -ForegroundColor Green
    } else {
        Write-Host "    ID: NOT PROVIDED" -ForegroundColor Red
    }
    Write-Host ""

    Write-Host "  Channel ID:" -ForegroundColor Gray
    if ($DiscordConfig.ChannelId) {
        Write-Host "    ID: $($DiscordConfig.ChannelId)" -ForegroundColor Green
    } else {
        Write-Host "    ID: NOT PROVIDED" -ForegroundColor Red
    }
    Write-Host ""

    # Installation Location
    Write-Host "Installation Location:" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ""
    $installPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
    Write-Host "  Path: $installPath" -ForegroundColor Cyan
    Write-Host ""

    # Readiness Check
    $pythonOk = $Prerequisites.Python.Found
    $ffmpegOk = $Prerequisites.FFmpeg.Found
    $voicemeterOk = $Prerequisites.VoiceMeeter.Found
    $discordOk = -not [string]::IsNullOrEmpty($DiscordConfig.BotToken) -and `
                 -not [string]::IsNullOrEmpty($DiscordConfig.ServerId) -and `
                 -not [string]::IsNullOrEmpty($DiscordConfig.ChannelId)

    Write-Host "Readiness Check:" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ""

    if ($pythonOk -and $ffmpegOk -and $voicemeterOk -and $discordOk) {
        Write-Host "  ✓ All prerequisites met" -ForegroundColor Green
        Write-Host "  ✓ All Discord configuration provided" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Status: READY TO INSTALL" -ForegroundColor Green -BackgroundColor DarkGreen
        $canProceed = $true
    } else {
        Write-Host "  ✗ Missing requirements:" -ForegroundColor Red
        if (-not $pythonOk) { Write-Host "    - Python not found" -ForegroundColor Red }
        if (-not $ffmpegOk) { Write-Host "    - FFmpeg not found" -ForegroundColor Red }
        if (-not $voicemeterOk) { Write-Host "    - VoiceMeeter not found" -ForegroundColor Red }
        if (-not $discordOk) { Write-Host "    - Discord configuration incomplete" -ForegroundColor Red }
        Write-Host ""
        Write-Host "  Status: CANNOT PROCEED" -ForegroundColor Red -BackgroundColor DarkRed
        $canProceed = $false
    }
    Write-Host ""

    return @{
        CanProceed = $canProceed
        InstallPath = $installPath
    }
}

Export-ModuleMember -Function Show-InstallationSummary
