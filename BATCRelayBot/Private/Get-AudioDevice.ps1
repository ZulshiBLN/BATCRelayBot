#Requires -Version 5.1

<#
.SYNOPSIS
Enumerates DirectShow audio devices and lets the user pick one.

.DESCRIPTION
bot.py streams with `-f dshow -i audio=<name>`, so config.json needs the
device name spelled exactly as ffmpeg reports it. Asking the user to type it
is how you get a bot that connects to Discord and then silently streams
nothing, so the name is read back from the same ffmpeg binary that will
later use it.
#>

function Get-DshowAudioDevice {
    <#
    .SYNOPSIS
    Returns the DirectShow audio device names ffmpeg can see.

    .DESCRIPTION
    `ffmpeg -list_devices true` writes to stderr and always exits non-zero
    ("Immediate exit requested"), so neither is treated as failure.

    Two output formats are parsed: ffmpeg >= 5 tags each line with (audio),
    older builds group devices under a "DirectShow audio devices" heading.

    .OUTPUTS
    [string[]] device names, empty if none could be enumerated.
    #>
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FFmpegPath
    )

    if (-not (Test-Path $FFmpegPath)) { return @() }

    try {
        $output = & $FFmpegPath -hide_banner -list_devices true -f dshow -i dummy 2>&1 |
            ForEach-Object { "$_" }
    } catch {
        return @()
    }

    if (-not $output) { return @() }

    $devices = New-Object System.Collections.Generic.List[string]
    $inAudioSection = $false

    foreach ($line in $output) {
        # Never mistake the alternative-name line for a device.
        if ($line -match 'Alternative name') { continue }

        if ($line -match 'DirectShow audio devices') { $inAudioSection = $true;  continue }
        if ($line -match 'DirectShow video devices') { $inAudioSection = $false; continue }

        if ($line -match '"([^"]+)"\s*\(audio\)') {
            if (-not $devices.Contains($Matches[1])) { $devices.Add($Matches[1]) }
            continue
        }
        if ($line -match '"([^"]+)"\s*\(video\)') { continue }

        if ($inAudioSection -and $line -match '"([^"]+)"') {
            if (-not $devices.Contains($Matches[1])) { $devices.Add($Matches[1]) }
        }
    }

    return $devices.ToArray()
}

function Select-AudioDevice {
    <#
    .SYNOPSIS
    Prompts the user to choose the recording device to stream from.

    .DESCRIPTION
    Presents the enumerated devices as a numbered list with the most likely
    VoiceMeeter output preselected. Falls back to manual entry when ffmpeg is
    unavailable or reports nothing, so a missing device list slows the user
    down instead of stopping the install.

    .OUTPUTS
    The chosen device name, or $null if the user aborted.
    #>
    [OutputType([string])]
    param(
        [string]$FFmpegPath,
        [string]$LogPath
    )

    Write-Host "Audio Device" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "The bot streams whatever this device records into Discord." -ForegroundColor Gray
    Write-Host ""

    $devices = @()
    if ($FFmpegPath) {
        $devices = @(Get-DshowAudioDevice -FFmpegPath $FFmpegPath)
    }

    if ($devices.Count -eq 0) {
        Write-Host "  Could not read the device list from ffmpeg." -ForegroundColor Yellow
        Write-Host "  Make sure VoiceMeeter is running, then enter the name manually." -ForegroundColor Yellow
        Write-Host "  It must match exactly what ffmpeg reports, for example:" -ForegroundColor Gray
        Write-Host "    VoiceMeeter Output (VB-Audio VoiceMeeter VAIO)" -ForegroundColor Gray
        Write-Host ""
        Write-InstallLog "Audio device enumeration returned nothing; falling back to manual entry" -LogPath $LogPath

        $manual = Read-Host "Device name"
        if ([string]::IsNullOrWhiteSpace($manual)) { return $null }
        return $manual.Trim()
    }

    # VoiceMeeter's own outputs are what this bot exists to relay, so surface
    # them first as the default.
    $preferred = 0
    for ($i = 0; $i -lt $devices.Count; $i++) {
        if ($devices[$i] -match 'Voicemeeter' -and $devices[$i] -match 'Out') { $preferred = $i; break }
        if ($devices[$i] -match 'Voicemeeter' -and $preferred -eq 0) { $preferred = $i }
    }

    Write-Host "  Recording devices reported by ffmpeg:" -ForegroundColor Gray
    Write-Host ""
    for ($i = 0; $i -lt $devices.Count; $i++) {
        $marker = if ($i -eq $preferred) { " (recommended)" } else { "" }
        $color = if ($i -eq $preferred) { "Green" } else { "Gray" }
        Write-Host ("    [{0}] {1}{2}" -f ($i + 1), $devices[$i], $marker) -ForegroundColor $color
    }
    Write-Host ""

    while ($true) {
        $answer = Read-Host ("Select device (1-{0}), [Enter] for {1}" -f $devices.Count, ($preferred + 1))

        if ([string]::IsNullOrWhiteSpace($answer)) {
            $selected = $devices[$preferred]
            Write-InstallLog "Audio device selected (default): $selected" -LogPath $LogPath
            Write-Host "  Selected: $selected" -ForegroundColor Green
            Write-Host ""
            return $selected
        }

        $index = 0
        if ([int]::TryParse($answer.Trim(), [ref]$index) -and $index -ge 1 -and $index -le $devices.Count) {
            $selected = $devices[$index - 1]
            Write-InstallLog "Audio device selected: $selected" -LogPath $LogPath
            Write-Host "  Selected: $selected" -ForegroundColor Green
            Write-Host ""
            return $selected
        }

        Write-Host "  Please enter a number between 1 and $($devices.Count)." -ForegroundColor Red
    }
}

Export-ModuleMember -Function @('Get-DshowAudioDevice', 'Select-AudioDevice')
