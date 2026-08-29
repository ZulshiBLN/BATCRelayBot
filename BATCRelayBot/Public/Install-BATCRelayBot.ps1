function Install-BATCRelayBot {
    <#
    .SYNOPSIS
    Installs all prerequisites and generates config.json for the BATC Relay Bot.

    .DESCRIPTION
    Installs Python, ffmpeg, and VoiceMeeter (via winget), pip dependencies, detects VoiceMeeter
    device, and interactively prompts for Discord configuration.
    Installs bot files to AppData\Local\BATCRelayBot. No admin rights required.

    .PARAMETER BotPath
    Installation path for bot files and configuration.
    Defaults to $env:USERPROFILE\AppData\Local\BATCRelayBot

    .EXAMPLE
    Install-BATCRelayBot

    .EXAMPLE
    Install-BATCRelayBot -BotPath "D:\MyBot\BATCRelayBot"
    #>

    param(
        [string]$BotPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
    )

    $ErrorActionPreference = "Stop"

    if (-not (Test-Path $BotPath)) {
        New-Item -ItemType Directory -Path $BotPath -Force | Out-Null
        Write-Host "Created bot directory: $BotPath" -ForegroundColor Green
    }

    Set-Location $BotPath

    # Copy bot files if they don't exist
    Write-Step "Preparing bot files"
    $moduleDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $sourceBot = Join-Path $moduleDir "bot.py"
    $sourceReqs = Join-Path $moduleDir "requirements.txt"
    $sourceConfig = Join-Path $moduleDir "config.example.json"

    if (Test-Path $sourceBot) {
        Copy-Item $sourceBot $BotPath -Force -ErrorAction SilentlyContinue
        Write-Host "bot.py copied to $BotPath" -ForegroundColor Green
    }
    if (Test-Path $sourceReqs) {
        Copy-Item $sourceReqs $BotPath -Force -ErrorAction SilentlyContinue
        Write-Host "requirements.txt copied to $BotPath" -ForegroundColor Green
    }
    if (Test-Path $sourceConfig) {
        Copy-Item $sourceConfig $BotPath -Force -ErrorAction SilentlyContinue
        Write-Host "config.example.json copied to $BotPath" -ForegroundColor Green
    }

    # Check winget
    Write-Step "Checking prerequisites"
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: winget (Windows Package Manager) not found." -ForegroundColor Red
        Write-Host "Install 'App Installer' from the Microsoft Store:" -ForegroundColor Red
        Write-Host "https://apps.microsoft.com/detail/9nblggh4nns1" -ForegroundColor Red
        exit 1
    }
    Write-Host "winget found." -ForegroundColor Green

    # Install Python
    Write-Step "Python"
    $pythonExe = Find-PerUserPython
    if ($pythonExe) {
        Write-Host "Python already installed: $pythonExe" -ForegroundColor Green
    } else {
        Write-Host "Python not found, installing latest via winget..." -ForegroundColor Cyan
        $searchOutput = winget search "Python.Python.3." --source winget --accept-source-agreements 2>$null
        $matches = [regex]::Matches(($searchOutput -join "`n"), 'Python\.Python\.3\.(\d+)')
        $latestId = $null
        $latestMinor = -1
        foreach ($m in $matches) {
            $minor = [int]$m.Groups[1].Value
            if ($minor -gt $latestMinor) {
                $latestMinor = $minor
                $latestId = $m.Value
            }
        }
        if (-not $latestId) {
            Write-Host "ERROR: Could not find Python via winget. Install manually from python.org" -ForegroundColor Red
            exit 1
        }
        Write-Host "Installing $latestId (current user only)..." -ForegroundColor Cyan
        winget install --id $latestId -e --scope user --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Python installation failed (exit code $LASTEXITCODE)." -ForegroundColor Red
            exit 1
        }
        $pythonExe = Find-PerUserPython
        if (-not $pythonExe) {
            Write-Host "ERROR: Python was installed but could not be located. Restart the terminal and try again." -ForegroundColor Red
            exit 1
        }
        Write-Host "Python installed: $pythonExe" -ForegroundColor Green
    }

    # Install ffmpeg
    Write-Step "ffmpeg"
    $ffmpegExe = Find-FfmpegExe
    if ($ffmpegExe) {
        Write-Host "ffmpeg already installed: $ffmpegExe" -ForegroundColor Green
    } else {
        Write-Host "ffmpeg not found, installing via winget..." -ForegroundColor Cyan
        winget install --id Gyan.FFmpeg -e --scope user --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: ffmpeg installation failed (exit code $LASTEXITCODE)." -ForegroundColor Red
            exit 1
        }
        $ffmpegExe = Find-FfmpegExe
        if (-not $ffmpegExe) {
            Write-Host "ERROR: ffmpeg was installed but could not be located." -ForegroundColor Red
            exit 1
        }
        Write-Host "ffmpeg installed: $ffmpegExe" -ForegroundColor Green
    }

    $ffmpegDir = Split-Path -Parent $ffmpegExe
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$ffmpegDir*") {
        Write-Host "Adding ffmpeg to user PATH: $ffmpegDir" -ForegroundColor Cyan
        $newUserPath = if ($userPath) { "$userPath;$ffmpegDir" } else { $ffmpegDir }
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    } else {
        Write-Host "ffmpeg is already on PATH." -ForegroundColor Green
    }

    if ($env:Path -notlike "*$ffmpegDir*") {
        $env:Path = "$env:Path;$ffmpegDir"
    }

    # Install VoiceMeeter
    Write-Step "VoiceMeeter"
    $voicemeeterInstalled = Get-ChildItem "C:\Program Files (x86)\VB\Voicemeeter\" -ErrorAction SilentlyContinue
    if ($voicemeeterInstalled) {
        Write-Host "VoiceMeeter already installed" -ForegroundColor Green
    } else {
        Write-Host "VoiceMeeter not found, installing via winget..." -ForegroundColor Cyan
        winget install --id VB-Audio.VoiceMeeter -e --scope user --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: VoiceMeeter installation may have failed (exit code $LASTEXITCODE)." -ForegroundColor Yellow
            Write-Host "VoiceMeeter requires restart. Please visit https://vb-audio.com/Voicemeeter/ to install manually if needed." -ForegroundColor Yellow
        } else {
            Write-Host "VoiceMeeter installed" -ForegroundColor Green
            Write-Host "NOTE: VoiceMeeter requires system restart to fully activate." -ForegroundColor Cyan
        }
    }

    # Install pip requirements
    Write-Step "Python dependencies"
    & $pythonExe -m pip install --upgrade pip --quiet
    & $pythonExe -m pip install -r (Join-Path $BotPath "requirements.txt")
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: pip install failed." -ForegroundColor Red
        exit 1
    }
    Write-Host "Python dependencies installed." -ForegroundColor Green

    # Detect VoiceMeeter
    Write-Step "Detecting VoiceMeeter device"
    $tempOut = New-TemporaryFile
    $tempErr = New-TemporaryFile
    Start-Process -FilePath $ffmpegExe -ArgumentList @("-list_devices", "true", "-f", "dshow", "-i", "dummy") `
        -RedirectStandardOutput $tempOut -RedirectStandardError $tempErr -NoNewWindow -Wait
    $listOutput = (Get-Content $tempOut -Raw -ErrorAction SilentlyContinue) + "`n" + (Get-Content $tempErr -Raw -ErrorAction SilentlyContinue)
    Remove-Item $tempOut, $tempErr -ErrorAction SilentlyContinue

    $deviceMatches = [regex]::Matches($listOutput, '"(Voicemeeter Out [^"]+)"\s*\(audio\)')
    $devices = $deviceMatches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

    if ($devices.Count -eq 0) {
        Write-Host "No VoiceMeeter device found. Is VoiceMeeter installed and started?" -ForegroundColor Yellow
        $audioDeviceName = Prompt-WithDefault -Message "Enter device name manually" -Default $null
    } elseif ($devices.Count -eq 1) {
        $audioDeviceName = $devices[0]
        Write-Host "Found: $audioDeviceName" -ForegroundColor Green
    } else {
        Write-Host "Multiple VoiceMeeter devices found:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $devices.Count; $i++) {
            Write-Host "  [$i] $($devices[$i])"
        }
        $choice = -1
        while ($choice -lt 0 -or $choice -ge $devices.Count) {
            $raw = Read-Host "Which device? (enter number)"
            [int]::TryParse($raw, [ref]$choice) | Out-Null
        }
        $audioDeviceName = $devices[$choice]
    }

    # Ask for Discord config
    Write-Step "Discord bot configuration"
    $configPath = Join-Path $BotPath "config.json"
    $writeConfig = $true
    if (Test-Path $configPath) {
        $answer = Read-Host "config.json exists. Overwrite? (y/N)"
        if ($answer -notmatch '^[yY]') {
            $writeConfig = $false
            Write-Host "config.json will not be changed." -ForegroundColor Yellow
        }
    }

    if ($writeConfig) {
        Write-Host "Find your bot token at: https://discord.com/developers/applications" -ForegroundColor Cyan
        $secureToken = Read-Host "Bot token (input will not be shown)" -AsSecureString
        $botToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
        )

        Write-Host "Get IDs by enabling Developer Mode in Discord settings, then right-click." -ForegroundColor Cyan
        $guildId = Prompt-WithDefault -Message "Server ID (guild_id)" -Default $null
        $voiceChannelId = Prompt-WithDefault -Message "Voice channel ID" -Default $null

        $defaultVoicemeeterPath = "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter_x64.exe"
        if (-not (Test-Path $defaultVoicemeeterPath)) { $defaultVoicemeeterPath = $null }
        $voicemeeterPath = Prompt-FilePath -Message "Path to VoiceMeeter (voicemeeter_x64.exe)" -Filter "Programs (*.exe)|*.exe"
        if ([string]::IsNullOrWhiteSpace($voicemeeterPath) -and $defaultVoicemeeterPath) {
            $voicemeeterPath = $defaultVoicemeeterPath
        }
        $voicemeeterProcessName = [System.IO.Path]::GetFileNameWithoutExtension($voicemeeterPath)

        $batcPath = Prompt-FilePath -Message "Path to BeyondATC.exe" -Filter "Programs (*.exe)|*.exe"
        $batcProcessName = [System.IO.Path]::GetFileNameWithoutExtension($batcPath)

        $voicemeeterWait = Prompt-WithDefault -Message "Wait time after starting VoiceMeeter (seconds)" -Default "6"
        $batcWait = Prompt-WithDefault -Message "Wait time after starting BeyondATC (seconds)" -Default "8"

        $configObject = [ordered]@{
            bot_token                = $botToken
            guild_id                 = [int64]$guildId
            voice_channel_id         = [int64]$voiceChannelId
            audio_device_name        = $audioDeviceName
            python_path              = $pythonExe
            voicemeeter_path         = $voicemeeterPath
            voicemeeter_process_name = $voicemeeterProcessName
            voicemeeter_wait_seconds = [int]$voicemeeterWait
            batc_path                = $batcPath
            batc_process_name        = $batcProcessName
            batc_wait_seconds        = [int]$batcWait
        }

        $jsonContent = $configObject | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($configPath, $jsonContent, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "config.json created." -ForegroundColor Green
    }

    Write-Step "Setup complete"
    Write-Host "Technical prerequisites are installed and configured." -ForegroundColor Green
    Write-Host ""
    Write-Host "Still to do (manual):" -ForegroundColor Cyan
    Write-Host "  1. Create a Discord bot at https://discord.com/developers/applications" -ForegroundColor Cyan
    Write-Host "  2. Invite it to your server with 'Connect' and 'Speak' permissions" -ForegroundColor Cyan
    Write-Host "  3. Set channel permissions for the bot's role: View Channel, Connect, Speak" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Then start the bot with: Start-BATCRelayBot" -ForegroundColor Green
}

