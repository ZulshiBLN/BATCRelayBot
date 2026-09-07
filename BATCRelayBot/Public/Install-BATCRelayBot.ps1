#Requires -Version 5.1

function Install-BATCRelayBot {
    <#
    .SYNOPSIS
    Installs BATCRelayBot: checks prerequisites, collects configuration, writes config.json.

    .DESCRIPTION
    Six phases, in an order chosen so that nothing the user types can be
    wasted:

      1. Detect prerequisites (silent)
      2. Show what was found and what is missing
      3. Resolve missing tools - winget for Python/FFmpeg, guidance for
         VoiceMeeter and BeyondATC, which must be installed by their vendors
      4. Collect Discord credentials and pick the audio device
      5. Confirm the summary
      6. Install and report

    Phases 1-3 finish before anything is typed. Until 1.4.0 the credentials
    were collected in phase 3 and the readiness check ran in phase 4, so a
    missing tool discarded the token, server ID and channel ID that had just
    been entered.

    No administrator rights are required.

    .PARAMETER BotPath
    Installation directory. Defaults to $env:LOCALAPPDATA\BATCRelayBot.

    .PARAMETER SkipAudioDevice
    Skips audio device selection and leaves audio_device_name empty. The bot
    will not start until it is filled in - intended for unattended testing.

    .EXAMPLE
    Install-BATCRelayBot

    .EXAMPLE
    Install-BATCRelayBot -BotPath "D:\MyBot"

    .OUTPUTS
    Hashtable with Success, and on success InstallPath, ConfigPath, LogPath.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$BotPath = (Join-Path $env:LOCALAPPDATA "BATCRelayBot"),
        [switch]$SkipAudioDevice
    )

    $version = Get-ModuleVersion

    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host "   BATCRelayBot Installation (v$version)" -ForegroundColor Cyan
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host ""

    # The log has to exist before anything can fail. Creating it later is why
    # earlier versions left no trace of the failures users actually hit.
    $logPath = Initialize-InstallLog -InstallPath $BotPath -Version $version
    if ($logPath) {
        Write-Host "Log file: $logPath" -ForegroundColor DarkGray
        Write-Host ""
    }

    try {
        # ---- Phase 0: migrate an existing installation -------------------
        $configPath = Join-Path $BotPath "config.json"
        if (Test-Path $configPath) {
            $migration = Convert-LegacyBotConfig -ConfigPath $configPath
            if ($migration.Migrated) {
                Write-Host "Existing configuration migrated to the current schema:" -ForegroundColor Cyan
                foreach ($change in $migration.Changes) {
                    Write-Host "  - $change" -ForegroundColor Gray
                }
                Write-InstallLog "Migrated existing config: $($migration.Changes -join '; ')" -LogPath $logPath
                Write-Host ""
            } elseif ($migration.Error) {
                Write-Host "WARNING: $($migration.Error)" -ForegroundColor Yellow
                Write-Host "         It will be replaced by this installation." -ForegroundColor Yellow
                Write-InstallLog "Migration skipped: $($migration.Error)" -LogPath $logPath -Level WARN
                Write-Host ""
            }
        }

        # ---- Phase 1: detection ------------------------------------------
        Write-Host "[1/6] Checking prerequisites..." -ForegroundColor Cyan
        $prerequisites = @{
            Python      = Find-Python
            FFmpeg      = Find-FFmpeg
            VoiceMeeter = Find-VoiceMeeter
            BeyondATC   = Find-BeyondATC
        }
        foreach ($name in @('Python', 'FFmpeg', 'VoiceMeeter', 'BeyondATC')) {
            $item = $prerequisites[$name]
            $detail = if ($item.Found) { $item.Path } else { $item.Reason }
            Write-InstallLog "Detected ${name}: Found=$($item.Found) - $detail" -LogPath $logPath
        }
        Write-Host ""

        # ---- Phase 2: status ---------------------------------------------
        Write-Host "[2/6] Prerequisite status" -ForegroundColor Cyan
        Show-PrerequisitesInfo -Prerequisites $prerequisites

        # ---- Phase 3: resolve what is missing ----------------------------
        Write-Host "[3/6] Resolving missing components" -ForegroundColor Cyan
        Write-Host ""

        $prerequisites = Resolve-MissingTool -Prerequisites $prerequisites -LogPath $logPath

        if (-not ($prerequisites.Python.Found -and $prerequisites.FFmpeg.Found)) {
            $stillMissing = @()
            if (-not $prerequisites.Python.Found) { $stillMissing += "Python" }
            if (-not $prerequisites.FFmpeg.Found) { $stillMissing += "FFmpeg" }

            $verb = if ($stillMissing.Count -eq 1) { "is" } else { "are" }
            Write-Host "$($stillMissing -join ' and ') $verb required and still missing." -ForegroundColor Red
            Write-Host ""
            if (-not $prerequisites.Python.Found) {
                Write-Host "  Python : https://www.python.org/downloads/  (tick 'Add python.exe to PATH')" -ForegroundColor Yellow
                Write-Host "           $($prerequisites.Python.Reason)" -ForegroundColor DarkGray
            }
            if (-not $prerequisites.FFmpeg.Found) {
                Write-Host "  FFmpeg : winget install Gyan.FFmpeg  -  or https://ffmpeg.org/download.html" -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "Install what is missing, then run Install-BATCRelayBot again." -ForegroundColor Yellow
            Write-InstallLog "Aborted: required tools still missing after phase 3" -LogPath $logPath -Level ERROR
            return (Stop-Installation -Reason "Required tools missing" -LogPath $logPath)
        }

        # VoiceMeeter has to come from VB-Audio's own installer, so the most
        # this installer can do is check, explain and let the user decide.
        if (-not $prerequisites.VoiceMeeter.Found) {
            if (-not (Confirm-ContinueWithoutVoiceMeeter -Detail $prerequisites.VoiceMeeter.Reason -LogPath $logPath)) {
                Write-InstallLog "User aborted at the VoiceMeeter warning" -LogPath $logPath
                return (Stop-Installation -Reason "Cancelled - VoiceMeeter missing" -LogPath $logPath)
            }
        }

        Show-BeyondATCNotice -BeyondATC $prerequisites.BeyondATC

        # ---- Phase 4: configuration --------------------------------------
        Write-Host "[4/6] Configuration" -ForegroundColor Cyan
        Write-Host ""

        $discordConfig = Get-DiscordConfiguration -LogPath $logPath
        if (-not $discordConfig) {
            Write-Host "Discord configuration was not completed." -ForegroundColor Red
            Write-InstallLog "Aborted: Discord configuration incomplete" -LogPath $logPath -Level ERROR
            return (Stop-Installation -Reason "Discord configuration incomplete" -LogPath $logPath)
        }

        if ($SkipAudioDevice) {
            $discordConfig.AudioDeviceName = ""
            Write-InstallLog "Audio device selection skipped by -SkipAudioDevice" -LogPath $logPath -Level WARN
        } else {
            $device = Select-AudioDevice -FFmpegPath $prerequisites.FFmpeg.Path -LogPath $logPath
            if (-not $device) {
                Write-Host "No audio device selected - the bot would join the channel but stream silence." -ForegroundColor Red
                Write-InstallLog "Aborted: no audio device selected" -LogPath $logPath -Level ERROR
                return (Stop-Installation -Reason "No audio device selected" -LogPath $logPath)
            }
            $discordConfig.AudioDeviceName = $device
        }

        # ---- Phase 5: summary --------------------------------------------
        Write-Host "[5/6] Summary" -ForegroundColor Cyan
        $summary = Show-InstallationSummary -Prerequisites $prerequisites `
            -DiscordConfig $discordConfig -InstallPath $BotPath

        if (-not $summary.CanProceed) {
            Write-Host "Installation cannot proceed: $($summary.BlockingReason)" -ForegroundColor Red
            Write-InstallLog "Aborted at summary: $($summary.BlockingReason)" -LogPath $logPath -Level ERROR
            return (Stop-Installation -Reason $summary.BlockingReason -LogPath $logPath)
        }

        # ---- Phase 6: install --------------------------------------------
        Write-Host "[6/6] Installing" -ForegroundColor Cyan
        $installResult = Start-Installation -Prerequisites $prerequisites `
            -DiscordConfig $discordConfig -InstallPath $BotPath -LogPath $logPath

        if (-not $installResult.Success) {
            Write-Host ""
            Write-Host "Installation failed: $($installResult.Error)" -ForegroundColor Red
            Write-InstallLog "Installation failed: $($installResult.Error)" -LogPath $logPath -Level ERROR
            return (Stop-Installation -Reason $installResult.Error -LogPath $logPath)
        }

        Show-PostInstallationMessage `
            -InstallPath $installResult.InstallPath `
            -ConfigPath $installResult.ConfigPath `
            -LogPath $installResult.LogPath

        Write-InstallLog "Installation completed successfully" -LogPath $logPath
        return $installResult

    } catch {
        # Nothing below this point may call exit: exit inside a module
        # function terminates the whole PowerShell session, which is what
        # made the window close before the error could be read.
        $message = Remove-SensitiveData -Text $_.Exception.Message

        Write-Host ""
        Write-Host "Unexpected error during installation:" -ForegroundColor Red
        Write-Host "  $message" -ForegroundColor Red
        Write-Host ""

        Write-InstallLog "Unhandled exception: $message" -LogPath $logPath -Level ERROR
        Write-InstallLog "At: $($_.ScriptStackTrace)" -LogPath $logPath -Level ERROR

        return (Stop-Installation -Reason $message -LogPath $logPath)
    }
}

function Stop-Installation {
    <#
    .SYNOPSIS
    Ends the installation without killing the host session.

    .DESCRIPTION
    Points the user at the log and pauses, so a double-clicked shortcut does
    not close before the message can be read. The pause is skipped when the
    session is non-interactive, otherwise automated runs would hang forever.
    #>
    [OutputType([hashtable])]
    param(
        [string]$Reason,
        [string]$LogPath
    )

    Write-Host ""
    if ($LogPath -and (Test-Path $LogPath)) {
        Write-Host "Details are in the log: $LogPath" -ForegroundColor Yellow
    }

    if ([Environment]::UserInteractive) {
        Write-Host ""
        Read-Host "Press Enter to close" | Out-Null
    }

    return @{ Success = $false; Error = $Reason; LogPath = $LogPath }
}

function Resolve-MissingTool {
    <#
    .SYNOPSIS
    Offers to install missing Python/FFmpeg, then returns updated detection.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Prerequisites,
        [string]$LogPath
    )

    $missing = @()
    if (-not $Prerequisites.Python.Found) { $missing += "Python 3.10+" }
    if (-not $Prerequisites.FFmpeg.Found) { $missing += "FFmpeg" }

    if ($missing.Count -eq 0) {
        Write-Host "  Python and FFmpeg are present." -ForegroundColor Green
        Write-Host ""
        return $Prerequisites
    }

    Write-Host "  Missing: $($missing -join ', ')" -ForegroundColor Yellow
    if ($Prerequisites.Python.Reason -and -not $Prerequisites.Python.Found) {
        Write-Host "  Python: $($Prerequisites.Python.Reason)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "    [1] Install them now with winget (per-user, no admin rights)" -ForegroundColor Gray
    Write-Host "    [2] I will install them myself - show the links" -ForegroundColor Gray
    Write-Host "    [3] Continue without installing" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "  Choice (1/2/3), [Enter] for 1"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }
    Write-InstallLog "Missing-tool choice: $choice (missing: $($missing -join ', '))" -LogPath $LogPath
    Write-Host ""

    switch ($choice.Trim()) {
        "2" {
            Write-Host "  Python : https://www.python.org/downloads/" -ForegroundColor Yellow
            Write-Host "           During setup, tick 'Add python.exe to PATH'." -ForegroundColor Gray
            Write-Host "  FFmpeg : winget install Gyan.FFmpeg" -ForegroundColor Yellow
            Write-Host "           or https://ffmpeg.org/download.html" -ForegroundColor Gray
            Write-Host ""
            Write-Host "  Run Install-BATCRelayBot again once they are installed." -ForegroundColor Yellow
            Write-Host ""
            return $Prerequisites
        }
        "3" {
            return $Prerequisites
        }
        default {
            return (Install-MissingPrerequisite -Prerequisites $Prerequisites -LogPath $LogPath)
        }
    }
}

function Confirm-ContinueWithoutVoiceMeeter {
    <#
    .SYNOPSIS
    Explains why VoiceMeeter matters and asks whether to continue anyway.

    .DESCRIPTION
    VoiceMeeter must be installed and removed through VB-Audio's own
    installer - it ships audio drivers, so a third party silently installing
    or removing it is not safe. This installer therefore only checks and
    explains.
    #>
    [OutputType([bool])]
    param(
        [string]$Detail,
        [string]$LogPath
    )

    Write-Host "  VoiceMeeter was not found." -ForegroundColor Yellow
    if ($Detail) { Write-Host "  $Detail" -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host "  VoiceMeeter provides the virtual audio device this bot streams from." -ForegroundColor Gray
    Write-Host "  Without it there is nothing to relay into Discord." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  It has to be installed with VB-Audio's own installer, because it" -ForegroundColor Gray
    Write-Host "  ships audio drivers. Short version:" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    1. Download from https://vb-audio.com/Voicemeeter/" -ForegroundColor Cyan
    Write-Host "    2. Run the installer as administrator" -ForegroundColor Cyan
    Write-Host "    3. Reboot - the virtual audio devices only appear afterwards" -ForegroundColor Cyan
    Write-Host "    4. Start VoiceMeeter, then run Install-BATCRelayBot again" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Continuing now means the audio device list will be missing the" -ForegroundColor Yellow
    Write-Host "  VoiceMeeter outputs, so audio_device_name has to be fixed by hand later." -ForegroundColor Yellow
    Write-Host ""

    $answer = Read-Host "  Continue anyway? (y/N)"
    $continue = $answer -match '^(y|yes|j|ja)$'
    Write-InstallLog "VoiceMeeter missing - user chose to $(if ($continue) { 'continue' } else { 'abort' })" -LogPath $LogPath
    Write-Host ""
    return $continue
}

function Show-BeyondATCNotice {
    <#
    .SYNOPSIS
    Reports BeyondATC status. Informational only - it is optional and paid.
    #>
    param([hashtable]$BeyondATC)

    if ($BeyondATC.Found -and $BeyondATC.ExePath) {
        Write-Host "  BeyondATC found: $($BeyondATC.ExePath)" -ForegroundColor Green
        Write-Host "  It will be started automatically with the bot." -ForegroundColor Gray
    } elseif ($BeyondATC.Found) {
        Write-Host "  BeyondATC configuration found, but not the executable." -ForegroundColor Yellow
        Write-Host "  Add batc_path to config.json manually if you want it auto-started." -ForegroundColor Gray
    } else {
        Write-Host "  BeyondATC not installed - optional, the bot works without it." -ForegroundColor Gray
        Write-Host "  It is commercial software: https://beyondatc.net/" -ForegroundColor DarkGray
    }
    Write-Host ""
}

Export-ModuleMember -Function @(
    'Install-BATCRelayBot',
    'Resolve-MissingTool',
    'Confirm-ContinueWithoutVoiceMeeter',
    'Show-BeyondATCNotice',
    'Stop-Installation'
)
