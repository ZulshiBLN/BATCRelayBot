function Start-BATCRelayBot {
    <#
    .SYNOPSIS
    Starts the BATC Relay Bot in the background.

    .DESCRIPTION
    Reads config.json, starts VoiceMeeter and BeyondATC if not running,
    waits for them to initialize, then starts bot.py in the background.
    Logs output to logs\bot_output.log and logs\bot_error.log.

    .PARAMETER ProjectPath
    Path to the project directory. Defaults to the current directory.

    .EXAMPLE
    Start-BATCRelayBot -ProjectPath "C:\MyProjects\ATC-Relay-Bot"
    #>

    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    $ErrorActionPreference = "Stop"
    Set-Location $ProjectPath

    $configPath = Join-Path $ProjectPath "config.json"
    if (-not (Test-Path $configPath)) {
        Write-Host "ERROR: config.json not found at $configPath" -ForegroundColor Red
        Write-Host "Run Install-BATCRelayBot first or copy config.example.json to config.json" -ForegroundColor Red
        exit 1
    }

    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "ERROR: config.json is invalid JSON: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    $requiredFields = @("python_path", "voicemeeter_path", "voicemeeter_process_name", "batc_path", "batc_process_name")
    foreach ($field in $requiredFields) {
        if (-not $config.$field) {
            Write-Host "ERROR: field '$field' is missing in config.json" -ForegroundColor Red
            exit 1
        }
    }

    function Ensure-Running {
        param(
            [string]$DisplayName,
            [string]$ExePath,
            [string]$ProcessName,
            [int]$WaitSecondsAfterStart
        )

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
    Ensure-Running -DisplayName "VoiceMeeter" -ExePath $config.voicemeeter_path `
        -ProcessName $config.voicemeeter_process_name -WaitSecondsAfterStart $voicemeeterWait
    Ensure-Running -DisplayName "BeyondATC" -ExePath $config.batc_path `
        -ProcessName $config.batc_process_name -WaitSecondsAfterStart $batcWait

    Write-Host ""
    Write-Host "=== Starting bot ===" -ForegroundColor Cyan

    if (-not (Test-Path $config.python_path)) {
        Write-Host "ERROR: python_path in config.json does not exist: $($config.python_path)" -ForegroundColor Red
        exit 1
    }

    $pythonDir = Split-Path -Parent $config.python_path
    $pythonw = Join-Path $pythonDir "pythonw.exe"

    if (-not (Test-Path $pythonw)) {
        Write-Host "pythonw.exe not found - falling back to python.exe (console may briefly appear)." -ForegroundColor Yellow
        $pythonw = $config.python_path
    }

    $logsDir = Join-Path $ProjectPath "logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -Path $logsDir -ItemType Directory | Out-Null
    }

    $logFile = Join-Path $logsDir "bot_output.log"
    $errorLogFile = Join-Path $logsDir "bot_error.log"
    $pidFile = Join-Path $ProjectPath "bot.pid"

    if (Test-Path $pidFile) {
        $oldPid = Get-Content $pidFile -ErrorAction SilentlyContinue
        if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
            Write-Host "Bot is already running (PID $oldPid). Stop it first with Stop-BATCRelayBot." -ForegroundColor Yellow
            exit 0
        }
    }

    $process = Start-Process `
        -FilePath $pythonw `
        -ArgumentList "bot.py" `
        -WorkingDirectory $ProjectPath `
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

