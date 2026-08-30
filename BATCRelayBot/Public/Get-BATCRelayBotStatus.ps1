function Get-BATCRelayBotStatus {
    <#
    .SYNOPSIS
    Gets the current status of the BATC Relay Bot.

    .DESCRIPTION
    Checks whether the bot process is running, and returns detailed status information.

    .PARAMETER BotPath
    Path to the bot installation directory.
    Defaults to $env:USERPROFILE\AppData\Local\BATCRelayBot

    .EXAMPLE
    Get-BATCRelayBotStatus

    .EXAMPLE
    Get-BATCRelayBotStatus -BotPath "D:\MyBot\BATCRelayBot"

    .OUTPUTS
    PSCustomObject with properties: IsRunning, ProcessId, PidFile, Uptime, LogFiles
    #>

    param(
        [string]$BotPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
    )

    $pidFile = Join-Path $BotPath "bot.pid"
    $logFile = Join-Path $BotPath "logs\bot_output.log"
    $errorLogFile = Join-Path $BotPath "logs\bot_error.log"

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

