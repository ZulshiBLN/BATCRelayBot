function Uninstall-BATCRelayBot {
    <#
    .SYNOPSIS
    Uninstalls the BATC Relay Bot configuration and generated files.

    .DESCRIPTION
    Stops the bot (if running), securely deletes config.json (which contains
    your bot token), and removes generated files (logs, bot.pid, stop.signal).
    Optionally uninstalls Python and ffmpeg (with separate confirmation).

    Project files (bot.py, requirements.txt) are NOT deleted.

    .PARAMETER ProjectPath
    Path to the project directory. Defaults to the current directory.

    .EXAMPLE
    UnInstall-BATCRelayBot -ProjectPath "C:\MyProjects\ATC-Relay-Bot"
    #>

    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    Set-Location $ProjectPath

    Write-Host "This will remove config.json (with your bot token), logs, and generated files." -ForegroundColor Cyan
    Write-Host "Project files (bot.py, requirements.txt) will NOT be deleted." -ForegroundColor Cyan

    function Confirm-Action {
        param([string]$Message)
        $answer = Read-Host "$Message (y/N)"
        return ($answer -match '^[yY]')
    }

    if (-not (Confirm-Action "Continue?")) {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }

    # Stop the bot
    Write-Step "Stopping bot (if running)"
    $pidFile = Join-Path $ProjectPath "bot.pid"
    $stopSignalFile = Join-Path $ProjectPath "stop.signal"

    if (Test-Path $pidFile) {
        $botPid = Get-Content $pidFile -ErrorAction SilentlyContinue
        if ($botPid -and (Get-Process -Id $botPid -ErrorAction SilentlyContinue)) {
            Write-Host "Stopping bot (PID $botPid)..." -ForegroundColor Cyan
            New-Item -Path $stopSignalFile -ItemType File -Force | Out-Null
            $waited = 0
            while ((Get-Process -Id $botPid -ErrorAction SilentlyContinue) -and $waited -lt 15) {
                Start-Sleep -Seconds 1
                $waited++
            }
            if (Get-Process -Id $botPid -ErrorAction SilentlyContinue) {
                Stop-Process -Id $botPid -Force
            }
            Write-Host "Bot stopped." -ForegroundColor Green
        } else {
            Write-Host "bot.pid exists but process not running." -ForegroundColor Green
        }
    } else {
        Write-Host "Bot is not running." -ForegroundColor Green
    }

    # Securely delete config.json
    Write-Step "Removing configuration and generated files"
    $configPath = Join-Path $ProjectPath "config.json"
    if (Test-Path $configPath) {
        Write-Host "Securely deleting config.json..." -ForegroundColor Cyan
        try {
            $fileInfo = Get-Item $configPath
            $size = $fileInfo.Length
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            for ($pass = 0; $pass -lt 2; $pass++) {
                $randomBytes = New-Object byte[] $size
                $rng.GetBytes($randomBytes)
                [System.IO.File]::WriteAllBytes($configPath, $randomBytes)
            }
            $rng.Dispose()
        } catch {
            Write-Host "Could not overwrite config.json (continuing with normal delete)." -ForegroundColor Yellow
        }
        Remove-Item $configPath -Force
        Write-Host "config.json deleted." -ForegroundColor Green
    }

    # Remove generated files
    foreach ($item in @($pidFile, $stopSignalFile)) {
        if (Test-Path $item) {
            Remove-Item $item -Force -ErrorAction SilentlyContinue
        }
    }

    $logsDir = Join-Path $ProjectPath "logs"
    if (Test-Path $logsDir) {
        Remove-Item $logsDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "logs\ folder removed." -ForegroundColor Green
    }

    # Optionally uninstall Python
    Write-Step "Python"
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "winget not found - skipping Python/ffmpeg uninstall options." -ForegroundColor Yellow
    } else {
        $listOutput = winget list --source winget 2>$null | Out-String
        if ($listOutput -match 'Python\.Python\.3') {
            Write-Host "Found installed Python package." -ForegroundColor Cyan
            Write-Host "NOTE: This removes Python from your system entirely." -ForegroundColor Yellow
            if (Confirm-Action "Uninstall Python?") {
                $match = [regex]::Match(($listOutput -join "`n"), 'Python\.Python\.3\.(\d+)')
                if ($match.Success) {
                    winget uninstall --id $match.Value --scope user --silent
                    Write-Host "Python uninstalled." -ForegroundColor Green
                }
            }
        }

        # Optionally uninstall ffmpeg
        Write-Step "ffmpeg"
        if ($listOutput -match "Gyan.FFmpeg") {
            Write-Host "Found Gyan.FFmpeg package." -ForegroundColor Cyan
            Write-Host "NOTE: This removes ffmpeg from your system entirely." -ForegroundColor Yellow
            if (Confirm-Action "Uninstall ffmpeg?") {
                winget uninstall --id Gyan.FFmpeg --scope user --silent
                $wingetPkgDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
                if (Test-Path $wingetPkgDir) {
                    $found = Get-ChildItem $wingetPkgDir -Filter "ffmpeg.exe" -Recurse -ErrorAction SilentlyContinue |
                        Where-Object { $_.FullName -match "Gyan\.FFmpeg" } |
                        Select-Object -First 1
                    if ($found) {
                        $ffmpegDir = Split-Path -Parent $found.FullName
                        $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
                        if ($userPath -like "*$ffmpegDir*") {
                            $cleanedPath = ($userPath -split ';' | Where-Object { $_ -and $_ -ne $ffmpegDir }) -join ';'
                            [Environment]::SetEnvironmentVariable("Path", $cleanedPath, "User")
                            Write-Host "Removed ffmpeg from PATH." -ForegroundColor Green
                        }
                    }
                }
                Write-Host "ffmpeg uninstalled." -ForegroundColor Green
            }
        }
    }

    Write-Step "Uninstall finished"
    Write-Host "Configuration and generated files have been removed." -ForegroundColor Green
    Write-Host "Project files (bot.py, requirements.txt) remain in place." -ForegroundColor Cyan
}

