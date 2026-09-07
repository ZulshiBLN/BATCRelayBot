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

Picking the right one out of the list matters just as much. A VoiceMeeter
install exposes a recording device per bus, and they are not
interchangeable:

  B1, B2, B3   virtual buses. Nothing is wired to them physically; they exist
               so other software can capture what VoiceMeeter mixes. This is
               what the bot needs, and README step 3 tells users to enable B1
               on the Virtual Input strip.

  A1 ... A5    physical buses, feeding speakers or headphones. Capturing one
               is not what the routing instructions set up.

ffmpeg lists devices in no useful order, so choosing "the first one that says
Voicemeeter and Out" picks whichever the enumeration happened to return
first - on the machine this was found on, that was B3 while the routing
guide had set up B1.
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

function Get-AudioDeviceInfo {
    <#
    .SYNOPSIS
    Classifies one device name into what it is good for.

    .DESCRIPTION
    Recognises both VoiceMeeter naming schemes:

      current   "Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)"
      older     "VoiceMeeter Output"      -> B1
                "VoiceMeeter Aux Output"  -> B2
                "VoiceMeeter VAIO3 Output"-> B3

    Rank orders the candidates; only virtual buses are ever recommendable.

    .OUTPUTS
    Hashtable with Name, IsVoiceMeeter, Bus, IsVirtual, Rank, Note.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    $info = @{
        Name          = $Name
        IsVoiceMeeter = $false
        Bus           = $null
        IsVirtual     = $false
        Rank          = 99
        Note          = "not a VoiceMeeter bus"
    }

    if ($Name -notmatch 'Voicemeeter') { return $info }
    $info.IsVoiceMeeter = $true

    # Current scheme: an explicit bus label.
    if ($Name -match 'Out\s+([AB])(\d+)') {
        $letter = $Matches[1].ToUpper()
        $number = [int]$Matches[2]
        $info.Bus = "$letter$number"

        if ($letter -eq 'B') {
            $info.IsVirtual = $true
            # B1 first: that is the bus README step 3 sets up.
            $info.Rank = if ($number -le 3) { $number } else { 4 }
            $info.Note = "virtual bus - can be captured"
        } else {
            $info.Rank = 90
            $info.Note = "physical output (speakers/headphones)"
        }
        return $info
    }

    # Older scheme: check the qualified names before the bare one.
    if ($Name -match 'Aux\s+Output') {
        $info.Bus = 'B2'; $info.IsVirtual = $true; $info.Rank = 2
        $info.Note = "virtual bus - can be captured"
        return $info
    }
    if ($Name -match 'VAIO3\s+Output') {
        $info.Bus = 'B3'; $info.IsVirtual = $true; $info.Rank = 3
        $info.Note = "virtual bus - can be captured"
        return $info
    }
    if ($Name -match 'Output') {
        $info.Bus = 'B1'; $info.IsVirtual = $true; $info.Rank = 1
        $info.Note = "virtual bus - can be captured"
        return $info
    }

    $info.Rank = 95
    $info.Note = "VoiceMeeter device of unknown type"
    return $info
}

function Get-RankedAudioDevice {
    <#
    .SYNOPSIS
    Orders devices so the capturable VoiceMeeter buses come first.

    .DESCRIPTION
    ffmpeg's own order is arbitrary, so the list is rebuilt: virtual buses in
    bus order, then everything else in the order ffmpeg reported it.

    .OUTPUTS
    Array of the hashtables from Get-AudioDeviceInfo, best candidate first.
    #>
    [OutputType([hashtable[]])]
    param([string[]]$Devices)

    $annotated = @()
    $index = 0
    foreach ($device in $Devices) {
        $info = Get-AudioDeviceInfo -Name $device
        $info.Order = $index++
        $annotated += $info
    }

    # Script blocks, not property names: Sort-Object resolves a bare property
    # name against the PSObject adapter, and for a hashtable that exposes
    # Count/Keys/Values - not the keys themselves. Sorting by 'Rank' silently
    # did nothing and left the list in enumeration order.
    return @($annotated | Sort-Object -Property { $_.Rank }, { $_.Order })
}

function Select-AudioDevice {
    <#
    .SYNOPSIS
    Prompts the user to choose the recording device to stream from.

    .DESCRIPTION
    Only the VoiceMeeter B buses are offered, with B1 preselected. Everything
    else on a machine - A buses feeding speakers, microphones, headsets - is
    not something this bot should ever relay, so listing it only invites the
    mistake. On the machine this was built against that turns a list of twelve
    into a list of three.

    Two fallbacks keep the shortened list from becoming a dead end:
    ffmpeg reporting nothing at all drops to manual entry, and no B bus being
    present (usually VoiceMeeter not running) shows the full list with a
    warning rather than leaving nothing to choose.

    In that fallback there is deliberately no default. Preselecting whatever
    came first would put a live microphone one keystroke from being relayed
    into a voice channel.

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
        Write-Host "    Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)" -ForegroundColor Gray
        Write-Host ""
        Write-InstallLog "Audio device enumeration returned nothing; falling back to manual entry" -LogPath $LogPath

        $manual = Read-Host "Device name"
        if ([string]::IsNullOrWhiteSpace($manual)) { return $null }
        return $manual.Trim()
    }

    $ordered = @(Get-RankedAudioDevice -Devices $devices)
    $virtual = @($ordered | Where-Object { $_.IsVirtual })

    if ($virtual.Count -gt 0) {
        # Physical buses and microphones are filtered out entirely: they are
        # never the right answer for this bot, and offering them is how the
        # wrong bus got picked in the first place.
        $all = $virtual
        $hasDefault = $true

        Write-Host "  VoiceMeeter virtual buses:" -ForegroundColor Gray
        Write-Host ""
        for ($i = 0; $i -lt $all.Count; $i++) {
            $marker = if ($i -eq 0) { "   <- recommended" } else { "" }
            $color = if ($i -eq 0) { "Green" } else { "Gray" }
            Write-Host ("    [{0}] {1}{2}" -f ($i + 1), $all[$i].Name, $marker) -ForegroundColor $color
        }
        Write-Host ""
        Write-Host "  B1 is the bus the setup guide routes audio to (README step 3)." -ForegroundColor DarkGray
        Write-Host "  Physical outputs and microphones are not listed - the bot cannot use them." -ForegroundColor DarkGray
        Write-Host ""
    } else {
        # No B bus at all, almost always because VoiceMeeter is not running.
        # Showing everything beats leaving an empty list.
        $all = $ordered
        $hasDefault = $false

        Write-Host "  No VoiceMeeter virtual bus (B1-B3) was found." -ForegroundColor Yellow
        Write-Host "  VoiceMeeter is probably not running - its buses only appear while it is." -ForegroundColor Yellow
        Write-Host "  Start it and run the installer again, or pick from everything ffmpeg sees:" -ForegroundColor Yellow
        Write-Host ""
        for ($i = 0; $i -lt $all.Count; $i++) {
            Write-Host ("    [{0}] {1}   ({2})" -f ($i + 1), $all[$i].Name, $all[$i].Note) -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-InstallLog "No VoiceMeeter B bus found; offering the full device list" -LogPath $LogPath -Level WARN
    }

    while ($true) {
        $prompt = if ($hasDefault) {
            "Select device (1-{0}), [Enter] for 1" -f $all.Count
        } else {
            "Select device (1-{0})" -f $all.Count
        }

        $answer = Read-Host $prompt

        if ([string]::IsNullOrWhiteSpace($answer)) {
            if (-not $hasDefault) {
                Write-Host "  Please pick a number - there is no safe default here." -ForegroundColor Red
                continue
            }
            $selected = $all[0].Name
            Write-InstallLog "Audio device selected (default, $($all[0].Bus)): $selected" -LogPath $LogPath
            Write-Host "  Selected: $selected" -ForegroundColor Green
            Write-Host ""
            return $selected
        }

        $index = 0
        if ([int]::TryParse($answer.Trim(), [ref]$index) -and $index -ge 1 -and $index -le $all.Count) {
            $choice = $all[$index - 1]

            if (-not $choice.IsVirtual) {
                Write-Host "  Note: $($choice.Note)." -ForegroundColor Yellow
                Write-Host "  That is usually not what you want to relay into Discord." -ForegroundColor Yellow
                $confirm = Read-Host "  Use it anyway? (y/N)"
                if ($confirm -notmatch '^(y|yes|j|ja)$') {
                    Write-Host ""
                    continue
                }
            }

            Write-InstallLog "Audio device selected: $($choice.Name)" -LogPath $LogPath
            Write-Host "  Selected: $($choice.Name)" -ForegroundColor Green
            Write-Host ""
            return $choice.Name
        }

        Write-Host "  Please enter a number between 1 and $($all.Count)." -ForegroundColor Red
    }
}

Export-ModuleMember -Function @(
    'Get-DshowAudioDevice',
    'Get-AudioDeviceInfo',
    'Get-RankedAudioDevice',
    'Select-AudioDevice'
)
