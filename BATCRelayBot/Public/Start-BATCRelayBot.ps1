function Start-BATCRelayBot {
    <#
    .SYNOPSIS
    Starts the BATC Relay Bot in the background.

    .DESCRIPTION
    Reads config.json, starts VoiceMeeter and BeyondATC if not running,
    waits for them to initialize, then starts bot.py in the background under
    a watcher process. The bot logs to logs\bot_output.log and
    logs\bot_error.log; the previous bot_error.log is kept aside, the last
    five in total. The watcher records how the bot ends - exit code and time -
    in install.log, which is the file to read when the bot has gone quiet.

    .PARAMETER BotPath
    Path to the bot installation directory.
    Defaults to $env:LOCALAPPDATA\BATCRelayBot

    .PARAMETER PidTimeoutSeconds
    How long to wait for the watcher to report the bot's process id.
    Defaults to 5.

    .EXAMPLE
    Start-BATCRelayBot

    .EXAMPLE
    Start-BATCRelayBot -BotPath "D:\MyBot\BATCRelayBot"
    #>

    param(
        [string]$BotPath = (Join-Path $env:LOCALAPPDATA "BATCRelayBot"),
        [int]$PidTimeoutSeconds = 5
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

    # A watcher with no bot is in its restart delay and about to start one.
    # Starting another here would end with two bots ten seconds later.
    $watchers = @(Find-BotWatcher -BotPath $BotPath)
    if ($watchers.Count -gt 0) {
        Write-Host "The bot's watcher (PID $($watchers -join ', ')) is still running and about to restart the bot." -ForegroundColor Yellow
        Write-Host "Wait a moment, or stop it first with Stop-BATCRelayBot." -ForegroundColor Yellow
        return
    }

    # Left over from a bot that is gone. Removing it keeps the next reader
    # from trusting it.
    if (Test-Path $pidFile) {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }

    # A stop.signal nobody consumed - a forced stop with no watcher to read
    # it - would stop the new bot within a second of coming up.
    Remove-Item (Join-Path $BotPath "stop.signal") -Force -ErrorAction SilentlyContinue

    # The watcher starts the bot, not this function: it is the process that
    # is still there when the bot dies, and the only one that can write down
    # how. It writes bot.pid with the child's id, which is waited for below.
    $watcher = Start-BotWatcher -BotPath $BotPath -Executable $pythonw

    # For a pid that names a live bot, not for the file to exist: the stale
    # removal above swallows failure, and existence alone could hand back the
    # old number.
    $botPid = $null
    $deadline = (Get-Date).AddSeconds($PidTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $text = Get-Content $pidFile -ErrorAction SilentlyContinue
        if ($text -match '^\d+$' -and (Test-BotPidAlive -ProcessId ([int]$text) -Executable $pythonw)) {
            $botPid = [int]$text
            break
        }
        Start-Sleep -Milliseconds 200
    }

    if ($null -eq $botPid) {
        Write-Host "The watcher (PID $($watcher.Id)) did not report a bot pid within $PidTimeoutSeconds second(s)." -ForegroundColor Yellow
        Write-Host "Check $(Join-Path $BotPath 'install.log') and $errorLogFile." -ForegroundColor Yellow
        Write-InstallLog -LogPath (Join-Path $BotPath "install.log") -Level WARN `
            -Message "Start-BATCRelayBot: watcher (PID $($watcher.Id)) did not report a bot pid within $PidTimeoutSeconds second(s)"
        return
    }

    Write-Host "Bot started (PID $botPid), watched by PID $($watcher.Id)." -ForegroundColor Green
    Write-Host "Output: $logFile" -ForegroundColor Cyan
    Write-Host "Errors: $errorLogFile" -ForegroundColor Cyan
    Write-Host "How it ends is recorded in: $(Join-Path $BotPath 'install.log')" -ForegroundColor Cyan
    Write-Host "Stop with: Stop-BATCRelayBot" -ForegroundColor Cyan
}

