#Requires -Version 5.1

<#
.SYNOPSIS
Phase 4 of setup: the token, the server ID and the audio device - kept from
the configuration that is already there, or asked for.

.DESCRIPTION
Every release that changes bot.py needs setup run again, and until 1.6.2
setup asked for all three values from scratch although phase 0 had just
migrated them. Now, when the file holds all three, setup shows them and asks
once whether to keep them; when it holds some, only the missing ones are
asked for; when it holds none, the three questions are asked as before.

A kept value is checked exactly like a typed one - the token against the
Discord API, the device against what ffmpeg lists - and one that fails is
asked for on its own. A token reset in the portal since the last setup is
caught here rather than at the next Start-BATCRelayBot.

The returned hashtable is keyed the way New-BotConfigFile expects: BotToken,
GuildId, AudioDeviceName. The names mirror bot.py's config keys rather than
the Discord UI wording; the old ServerId/ChannelId naming is what let the
installer write server_id and channel_id for sixteen releases while bot.py
read neither.
#>

function Resolve-BotConfiguration {
    <#
    .OUTPUTS
    Hashtable with BotToken, GuildId, AudioDeviceName - or $null when the
    user abandoned a prompt.
    #>
    [OutputType([hashtable])]
    param(
        [string]$ConfigPath,
        [string]$FFmpegPath,
        [switch]$SkipAudioDevice,
        [string]$LogPath
    )

    $existing = Get-ExistingConfiguration -ConfigPath $ConfigPath
    $complete = $existing.BotToken -and $existing.GuildId -and
                ($SkipAudioDevice -or $existing.AudioDeviceName)

    # Complete and declined: nothing is kept, the three questions follow.
    # Complete and kept, or partial: what is there is a candidate, and each
    # candidate still has to pass the check a typed value would.
    if ($complete -and -not (Confirm-KeepConfiguration -Existing $existing -SkipAudioDevice:$SkipAudioDevice)) {
        $existing = @{ BotToken = $null; GuildId = $null; AudioDeviceName = $null }
    }

    $config = @{ BotToken = $null; GuildId = $null; AudioDeviceName = $null }

    # The heading a clean run has always had. A run that keeps something
    # already had its own heading from the keep question.
    if (-not $existing.BotToken -and -not $existing.GuildId) {
        Write-Host "Discord Configuration" -ForegroundColor White -BackgroundColor DarkBlue
        Write-Host "Two values from the Discord developer portal and your server." -ForegroundColor Gray
        Write-Host ""
    }

    if ($existing.BotToken) {
        Write-Host "  Checking the stored token against the Discord API..." -ForegroundColor Gray
        $validation = Test-DiscordBotToken -Token $existing.BotToken
        if ($validation.Valid) {
            Write-Host "  Token accepted. Bot: $($validation.BotName)" -ForegroundColor Green
            Write-InstallLog "Stored token validated for bot '$($validation.BotName)'" -LogPath $LogPath
            $config.BotToken = $existing.BotToken
        } else {
            Write-Host "  The stored token was rejected: $($validation.Error)" -ForegroundColor Yellow
            Write-Host "  It may have been reset in the developer portal. A new one is needed." -ForegroundColor Yellow
            Write-InstallLog "Stored token rejected: $($validation.Error)" -LogPath $LogPath -Level WARN
        }
        Write-Host ""
    }
    if (-not $config.BotToken) {
        $config.BotToken = Read-DiscordToken -LogPath $LogPath
        if (-not $config.BotToken) { return $null }
    }

    if ($existing.GuildId -and ([string]$existing.GuildId) -match '^\d{17,21}$') {
        $config.GuildId = [string]$existing.GuildId
    } else {
        $config.GuildId = Read-DiscordSnowflake `
            -Label "Server ID (guild)" `
            -Step "Step 2/2" `
            -Hint "Discord: Settings > Advanced > Developer Mode, then right-click the server > Copy Server ID" `
            -LogPath $LogPath
        if (-not $config.GuildId) { return $null }
    }

    if ($SkipAudioDevice) {
        $config.AudioDeviceName = ""
        Write-InstallLog "Audio device selection skipped by -SkipAudioDevice" -LogPath $LogPath -Level WARN
        return $config
    }

    if ($existing.AudioDeviceName) {
        $listed = @()
        if ($FFmpegPath) { $listed = @(Get-DshowAudioDevice -FFmpegPath $FFmpegPath) }
        if ($listed -contains $existing.AudioDeviceName) {
            $config.AudioDeviceName = $existing.AudioDeviceName
            Write-InstallLog "Stored audio device still listed by ffmpeg: $($existing.AudioDeviceName)" -LogPath $LogPath
        } else {
            Write-Host "  The stored audio device is not in ffmpeg's list any more:" -ForegroundColor Yellow
            Write-Host "    $($existing.AudioDeviceName)" -ForegroundColor Gray
            Write-Host "  Is VoiceMeeter running? Pick again." -ForegroundColor Yellow
            Write-Host ""
            Write-InstallLog "Stored audio device no longer listed: $($existing.AudioDeviceName)" -LogPath $LogPath -Level WARN
        }
    }
    if (-not $config.AudioDeviceName) {
        $config.AudioDeviceName = Select-AudioDevice -FFmpegPath $FFmpegPath -LogPath $LogPath
        if (-not $config.AudioDeviceName) { return $null }
    }

    return $config
}

function Get-ExistingConfiguration {
    <#
    .SYNOPSIS
    The three asked-for values as config.json holds them after migration.
    Anything unreadable reads as absent; setup then asks, as it always did.
    #>
    [OutputType([hashtable])]
    param([string]$ConfigPath)

    $found = @{ BotToken = $null; GuildId = $null; AudioDeviceName = $null }
    if (-not $ConfigPath -or -not (Test-Path $ConfigPath)) { return $found }

    try {
        $raw = Get-Content $ConfigPath -Raw -Encoding UTF8 -ErrorAction Stop
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $found
    }

    foreach ($pair in @(@('BotToken', 'bot_token'), @('GuildId', 'guild_id'), @('AudioDeviceName', 'audio_device_name'))) {
        $value = $json.PSObject.Properties[$pair[1]].Value
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            $found[$pair[0]] = [string]$value
        }
    }
    return $found
}

function Confirm-KeepConfiguration {
    <#
    .SYNOPSIS
    Shows the three stored values - token redacted, server ID masked - and
    asks once whether to keep them. Enter, y or yes keeps.
    #>
    [OutputType([bool])]
    param(
        [hashtable]$Existing,
        [switch]$SkipAudioDevice
    )

    Write-Host "Existing configuration" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "Setup found these values in config.json." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Bot token     [REDACTED]" -ForegroundColor Gray
    Write-Host "  Server ID     $(Format-Snowflake $Existing.GuildId)" -ForegroundColor Gray
    if (-not $SkipAudioDevice) {
        Write-Host "  Audio device  $($Existing.AudioDeviceName)" -ForegroundColor Gray
    }
    Write-Host ""

    $answer = Read-Host "Keep this configuration? [Y/n]"
    Write-Host ""
    return ([string]::IsNullOrWhiteSpace($answer) -or $answer.Trim() -match '^(y|yes)$')
}

Export-ModuleMember -Function @(
    'Resolve-BotConfiguration',
    'Get-ExistingConfiguration',
    'Confirm-KeepConfiguration'
)
