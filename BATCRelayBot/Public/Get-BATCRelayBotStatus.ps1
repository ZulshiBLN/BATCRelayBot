function Get-BATCRelayBotStatus {
    <#
    .SYNOPSIS
    Gets the current status of the BATC Relay Bot.

    .DESCRIPTION
    Checks whether the bot process is running, and returns detailed status information.

    .PARAMETER ProjectPath
    Path to the project directory. Defaults to the current directory.

    .EXAMPLE
    Get-BATCRelayBotStatus
    Get-BATCRelayBotStatus -ProjectPath "C:\MyProjects\ATC-Relay-Bot"

    .OUTPUTS
    PSCustomObject with properties: IsRunning, ProcessId, PidFile, Uptime, LogFiles
    #>

    param(
        [string]$ProjectPath = (Get-Location).Path
    )

    $pidFile = Join-Path $ProjectPath "bot.pid"
    $logFile = Join-Path $ProjectPath "logs\bot_output.log"
    $errorLogFile = Join-Path $ProjectPath "logs\bot_error.log"

    $status = [PSCustomObject]@{
        IsRunning    = $false
        ProcessId    = $null
        PidFile      = $pidFile
        Uptime       = $null
        LogFile      = $logFile
        ErrorLogFile = $errorLogFile
        ProcessInfo  = $null
    }

    if (Test-Path $pidFile) {
        $botPid = Get-Content $pidFile -ErrorAction SilentlyContinue
        $process = Get-Process -Id $botPid -ErrorAction SilentlyContinue

        if ($process) {
            $status.IsRunning = $true
            $status.ProcessId = $botPid
            $status.ProcessInfo = $process
            $status.Uptime = (Get-Date) - $process.StartTime
        }
    }

    if ($status.IsRunning) {
        Write-Host "Bot Status: RUNNING" -ForegroundColor Green
        Write-Host "  PID: $($status.ProcessId)" -ForegroundColor Cyan
        Write-Host "  Uptime: $($status.Uptime.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan
    } else {
        Write-Host "Bot Status: NOT RUNNING" -ForegroundColor Yellow
    }

    Write-Host "  Output log: $($status.LogFile)" -ForegroundColor Cyan
    Write-Host "  Error log: $($status.ErrorLogFile)" -ForegroundColor Cyan

    return $status
}

