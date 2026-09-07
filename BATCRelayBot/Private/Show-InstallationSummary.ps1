#Requires -Version 5.1

<#
.SYNOPSIS
Shows what is about to be installed and whether it can proceed.

.DESCRIPTION
VoiceMeeter is no longer a hard gate here. It cannot be installed
automatically, and the user has already been shown the consequences and
chosen to continue in phase 3 - blocking again at this point would only
discard the credentials they just entered.

Returns BlockingReason alongside CanProceed so the caller can report *why*
rather than printing a generic "cannot proceed".
#>

function Show-InstallationSummary {
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Prerequisites,

        [Parameter(Mandatory = $true)]
        [hashtable]$DiscordConfig,

        [string]$InstallPath = (Join-Path $env:LOCALAPPDATA "BATCRelayBot")
    )

    Write-Host ""
    Write-Host "  Target        $InstallPath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Python        $($Prerequisites.Python.Path)" -ForegroundColor Gray
    Write-Host "  FFmpeg        $($Prerequisites.FFmpeg.Path)" -ForegroundColor Gray

    if ($Prerequisites.VoiceMeeter.Found) {
        Write-Host "  VoiceMeeter   $($Prerequisites.VoiceMeeter.ExePath)" -ForegroundColor Gray
    } else {
        Write-Host "  VoiceMeeter   not installed - audio will not work yet" -ForegroundColor Yellow
    }

    if ($Prerequisites.BeyondATC.Found -and $Prerequisites.BeyondATC.ExePath) {
        Write-Host "  BeyondATC     $($Prerequisites.BeyondATC.ExePath)" -ForegroundColor Gray
    } else {
        Write-Host "  BeyondATC     not configured (optional)" -ForegroundColor DarkGray
    }

    Write-Host ""
    # Never print any part of the token: the console scrollback outlives the
    # installer and often ends up pasted into a bug report.
    Write-Host "  Bot token     [REDACTED]" -ForegroundColor Gray
    Write-Host "  Server ID     $($DiscordConfig.GuildId)" -ForegroundColor Gray
    Write-Host "  Voice channel $($DiscordConfig.VoiceChannelId)" -ForegroundColor Gray

    if ([string]::IsNullOrWhiteSpace($DiscordConfig.AudioDeviceName)) {
        Write-Host "  Audio device  not set - the bot will stream silence" -ForegroundColor Yellow
    } else {
        Write-Host "  Audio device  $($DiscordConfig.AudioDeviceName)" -ForegroundColor Gray
    }
    Write-Host ""

    $blocking = @()
    if (-not $Prerequisites.Python.Found) { $blocking += "Python is missing" }
    if (-not $Prerequisites.FFmpeg.Found) { $blocking += "FFmpeg is missing" }
    if ([string]::IsNullOrWhiteSpace($DiscordConfig.BotToken)) { $blocking += "the bot token is missing" }
    if ([string]::IsNullOrWhiteSpace($DiscordConfig.GuildId)) { $blocking += "the server ID is missing" }
    if ([string]::IsNullOrWhiteSpace($DiscordConfig.VoiceChannelId)) { $blocking += "the voice channel ID is missing" }

    if ($blocking.Count -gt 0) {
        Write-Host "  Cannot proceed: $($blocking -join ', ')" -ForegroundColor Red
        Write-Host ""
        return @{
            CanProceed     = $false
            BlockingReason = ($blocking -join ', ')
            InstallPath    = $InstallPath
        }
    }

    Write-Host "  Ready to install." -ForegroundColor Green
    Write-Host ""

    return @{
        CanProceed     = $true
        BlockingReason = $null
        InstallPath    = $InstallPath
    }
}

Export-ModuleMember -Function 'Show-InstallationSummary'
