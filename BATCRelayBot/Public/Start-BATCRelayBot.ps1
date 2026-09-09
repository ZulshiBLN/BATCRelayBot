function Start-BATCRelayBot {
    <#
    .SYNOPSIS
    Starts the BATC Relay Bot in the background.

    .DESCRIPTION
    Reads config.json, starts VoiceMeeter and BeyondATC if not running,
    waits for them to initialize, then starts bot.py in the background.
    Logs output to logs\bot_output.log and logs\bot_error.log.

    .PARAMETER BotPath
    Path to the bot installation directory.
    Defaults to $env:LOCALAPPDATA\BATCRelayBot

    .EXAMPLE
    Start-BATCRelayBot

    .EXAMPLE
    Start-BATCRelayBot -BotPath "D:\MyBot\BATCRelayBot"
    #>

    param(
        [string]$BotPath = (Join-Path $env:LOCALAPPDATA "BATCRelayBot")
    )

    $ErrorActionPreference = "Stop"

    # No Set-Location: this is a module function, and moving the caller's
    # working directory is a side effect they did not ask for. Start-Process
    # gets -WorkingDirectory instead.

    $configPath = Join-Path $BotPath "config.json"
    if (-not (Test-Path $configPath)) {
        Write-Host "ERROR: config.json not found at $configPath" -ForegroundColor Red
        Write-Host "Run Install-BATCRelayBot first or copy config.example.json to config.json" -ForegroundColor Red
        return
    }

    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "ERROR: config.json is invalid JSON: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # Only python_path is genuinely required to start the bot. VoiceMeeter and
    # BeyondATC are launched if configured and skipped with a warning if not:
    # BeyondATC is optional commercial software, and treating it as mandatory
    # meant a perfectly valid installation refused to start without it.
    $requiredFields = @("python_path")
    foreach ($field in $requiredFields) {
        if (-not $config.$field) {
            Write-Host "ERROR: field '$field' is missing in config.json" -ForegroundColor Red
            Write-Host "Run Install-BATCRelayBot to regenerate the configuration." -ForegroundColor Yellow
            return
        }
    }

    function Start-ComponentIfNeeded {
        param(
            [string]$DisplayName,
            [string]$ExePath,
            [string]$ProcessName,
            [int]$WaitSecondsAfterStart
        )

        # Not configured at all - the component is optional or was skipped
        # during installation.
        if ([string]::IsNullOrWhiteSpace($ExePath) -or [string]::IsNullOrWhiteSpace($ProcessName)) {
            Write-Host "$DisplayName is not configured - skipping." -ForegroundColor DarkGray
            return
        }

        $running = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($running) {
            Write-Host "$DisplayName is already running." -ForegroundColor Green
            return
        }

        if (-not (Test-Path $ExePath)) {
            Write-Host "WARNING: $DisplayName not found at $ExePath - skipping." -ForegroundColor Yellow
            return
        }

        Write-Host "$DisplayName is not running - starting..." -ForegroundColor Cyan
        Start-Process -FilePath $ExePath | Out-Null
        Write-Host "Waiting $WaitSecondsAfterStart second(s) for $DisplayName to initialize..." -ForegroundColor Cyan
        Start-Sleep -Seconds $WaitSecondsAfterStart

        if (-not (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)) {
            Write-Host "WARNING: $DisplayName does not appear to be running - please check manually." -ForegroundColor Yellow
        }
    }

    $voicemeeterWait = if ($config.voicemeeter_wait_seconds) { $config.voicemeeter_wait_seconds } else { 6 }
    $batcWait = if ($config.batc_wait_seconds) { $config.batc_wait_seconds } else { 8 }

    Write-Host "=== Checking prerequisites ===" -ForegroundColor Cyan
    Start-ComponentIfNeeded -DisplayName "VoiceMeeter" -ExePath $config.voicemeeter_path `
        -ProcessName $config.voicemeeter_process_name -WaitSecondsAfterStart $voicemeeterWait
    Start-ComponentIfNeeded -DisplayName "BeyondATC" -ExePath $config.batc_path `
        -ProcessName $config.batc_process_name -WaitSecondsAfterStart $batcWait

    Write-Host ""
    Write-Host "=== Starting bot ===" -ForegroundColor Cyan

    if (-not (Test-Path $config.python_path)) {
        Write-Host "ERROR: python_path in config.json does not exist: $($config.python_path)" -ForegroundColor Red
        Write-Host "Run Install-BATCRelayBot again to re-detect Python." -ForegroundColor Yellow
        return
    }

    $pythonDir = Split-Path -Parent $config.python_path
    $pythonw = Join-Path $pythonDir "pythonw.exe"

    if (-not (Test-Path $pythonw)) {
        Write-Host "pythonw.exe not found - falling back to python.exe (console may briefly appear)." -ForegroundColor Yellow
        $pythonw = $config.python_path
    }

    $logsDir = Join-Path $BotPath "logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -Path $logsDir -ItemType Directory | Out-Null
    }

    $logFile = Join-Path $logsDir "bot_output.log"
    $errorLogFile = Join-Path $logsDir "bot_error.log"
    $pidFile = Join-Path $BotPath "bot.pid"

    # bot.pid is a hint, not the authority - the same lesson Stop-BATCRelayBot
    # learned and this function did not. A stale pid file let a second bot
    # start beside a running one on 2026-09-09. Both answered every chat
    # command, the second start truncated the first one's log, and
    # Stop-BATCRelayBot then waited fifteen seconds for a process that was
    # never going to answer and terminated it - which is how ffmpeg came to be
    # killed without releasing the VoiceMeeter bus it was capturing, taking
    # the machine's audio with it.
    $alreadyRunning = @(Find-BotProcess -BotPath $BotPath)

    if ($alreadyRunning.Count -gt 0) {
        Write-Host "Bot is already running (PID $($alreadyRunning -join ', '))." -ForegroundColor Yellow
        Write-Host "Stop it first with Stop-BATCRelayBot." -ForegroundColor Yellow
        return
    }

    # Left over from a bot that is gone. Removing it keeps the next reader
    # from trusting it.
    if (Test-Path $pidFile) {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }

    $process = Start-Process `
        -FilePath $pythonw `
        -ArgumentList "bot.py" `
        -WorkingDirectory $BotPath `
        -WindowStyle Hidden `
        -RedirectStandardOutput $logFile `
        -RedirectStandardError $errorLogFile `
        -PassThru

    $process.Id | Out-File -FilePath $pidFile -Encoding ascii

    Write-Host "Bot started (PID $($process.Id))." -ForegroundColor Green
    Write-Host "Output: $logFile" -ForegroundColor Cyan
    Write-Host "Errors: $errorLogFile" -ForegroundColor Cyan
    Write-Host "Stop with: Stop-BATCRelayBot" -ForegroundColor Cyan
}

