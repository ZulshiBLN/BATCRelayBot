#Requires -Version 5.1

function Show-ConfigEditorMenu {
    <#
    .SYNOPSIS
    Interactive menu for changing one configuration field.

    .DESCRIPTION
    Offers only the fields bot.py reads, taken from Get-ConfigFieldMap. Two
    earlier entries, output format and bot activity, are gone: bot.py never
    read them, so changing them did nothing.

    The menu does not clear the console. It used to call Clear-Host on every
    iteration, which wipes whatever the user had on screen - including the
    installer output they may still need.

    .PARAMETER ConfigPath
    Path to config.json.

    .PARAMETER FFmpegPath
    ffmpeg used to enumerate audio devices. Falls back to detection.

    .OUTPUTS
    Hashtable with Field and Value once a change is confirmed, or $null when
    the user quits.
    #>
    param(
        [string]$ConfigPath,
        [string]$FFmpegPath
    )

    if (-not (Test-Path $ConfigPath)) {
        # Write-Host, not Write-Error: this is an expected, handled condition
        # that the caller already reports. Writing to the error stream made
        # the outcome depend on the host's $ErrorActionPreference - the same
        # call passed locally and failed on the CI runner.
        Write-Host "  config.json not found: $ConfigPath" -ForegroundColor Red
        return $null
    }

    while ($true) {
        try {
            $config = Get-Content $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Error "config.json is not valid JSON: $($_.Exception.Message)"
            return $null
        }

        Write-Host ""
        Write-Host "BATCRelayBot Configuration" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1. Bot token          [REDACTED]" -ForegroundColor Gray
        Write-Host "  2. Server ID          $(Format-ConfigValue $config.guild_id)" -ForegroundColor Gray
        Write-Host "  3. Audio device       $(Format-ConfigValue $config.audio_device_name)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  q. Quit" -ForegroundColor Gray
        Write-Host ""

        # Read-Host returns "" for a bare Enter and $null only when there is no
        # input to be had. The difference matters now that the caller loops:
        # "" re-prompts, $null would otherwise re-prompt forever on a host that
        # cannot answer - and .Trim() on it threw before it got that far.
        $raw = try { Read-Host "Select field to edit (1-3) or q" } catch { $null }
        if ($null -eq $raw) {
            Write-Host "  (no input available - leaving the editor)" -ForegroundColor Yellow
            return $null
        }
        $selection = "$raw".Trim()

        $result = $null
        switch ($selection) {
            "1" { $result = Get-DiscordToken }
            "2" {
                $result = Read-ConfigSnowflake -Field "Guild" -CurrentValue $config.guild_id
            }
            "3" {
                $result = Read-ConfigAudioDevice -FFmpegPath $FFmpegPath -CurrentValue $config.audio_device_name
            }
            # Neither branch may claim nothing was changed: the caller returns
            # here after every change, so by the time q is pressed there may
            # have been several. Only the caller knows.
            "q" { return $null }
            "Q" { return $null }
            default {
                Write-Host "  Please choose 1-3, or q to quit." -ForegroundColor Yellow
                continue
            }
        }

        if (-not $result -or -not $result.Valid) {
            if ($result -and $result.Message) {
                Write-Host "  $($result.Message)" -ForegroundColor Yellow
            }
            continue
        }

        # Confirm before returning: this is the last point at which the change
        # can be abandoned without touching the file.
        Write-Host ""
        $confirm = Read-Host "  Apply this change? (y/N)"
        if ($confirm -notmatch '^(y|yes|j|ja)$') {
            Write-Host "  Discarded." -ForegroundColor Yellow
            continue
        }

        return @{ Field = $result.Field; Value = $result.Value }
    }
}

function Format-ConfigValue {
    <#
    .SYNOPSIS
    Renders a config value for display, naming the empty case explicitly.
    #>
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return "(not set)"
    }
    return [string]$Value
}

function Read-ConfigSnowflake {
    <#
    .SYNOPSIS
    Prompts for a Discord ID and validates it before returning.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][string]$Field,
        $CurrentValue
    )

    $definition = Get-ConfigFieldDefinition -Field $Field

    Write-Host ""
    Write-Host $definition.Label -ForegroundColor Cyan
    Write-Host "  Current: $(Format-ConfigValue $CurrentValue)" -ForegroundColor Gray
    Write-Host "  $($definition.Hint)" -ForegroundColor Gray
    Write-Host ""

    $entered = Read-Host "  New $($definition.Label) (Enter to cancel)"

    if ([string]::IsNullOrWhiteSpace($entered)) {
        return @{ Value = $null; Valid = $false; Message = "Cancelled - $($definition.Label) unchanged" }
    }

    $check = Test-ConfigValue -Field $Field -Value $entered.Trim()
    if (-not $check.Valid) {
        return @{ Value = $null; Valid = $false; Message = $check.Message }
    }

    return @{ Value = $entered.Trim(); Valid = $true; Message = $check.Message; Field = $Field }
}

function Read-ConfigAudioDevice {
    <#
    .SYNOPSIS
    Picks a new audio device from the same filtered list the installer uses.

    .DESCRIPTION
    Reuses Select-AudioDevice so the editor cannot offer a device the
    installer would reject, and so the name is always spelled exactly as
    ffmpeg reports it. This is the field most likely to need correcting after
    an install, because it is the one that decides whether anything is heard.
    #>
    [OutputType([hashtable])]
    param(
        [string]$FFmpegPath,
        $CurrentValue
    )

    Write-Host ""
    Write-Host "Audio device" -ForegroundColor Cyan
    Write-Host "  Current: $(Format-ConfigValue $CurrentValue)" -ForegroundColor Gray
    Write-Host ""

    if (-not $FFmpegPath) {
        $detected = Find-FFmpeg
        if ($detected.Found) { $FFmpegPath = $detected.Path }
    }

    $device = Select-AudioDevice -FFmpegPath $FFmpegPath

    if (-not $device) {
        return @{ Value = $null; Valid = $false; Message = "Cancelled - audio device unchanged" }
    }

    return @{ Value = $device; Valid = $true; Message = "Audio device selected"; Field = "AudioDevice" }
}

Export-ModuleMember -Function @(
    'Show-ConfigEditorMenu',
    'Format-ConfigValue',
    'Read-ConfigSnowflake',
    'Read-ConfigAudioDevice'
)
