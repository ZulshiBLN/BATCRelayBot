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
    PSCustomObject with properties: IsRunning, ProcessId, PidFile, Uptime,
    OrphanedFromPidFile, LogFile, ErrorLogFile, ProcessInfo
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
        OrphanedFromPidFile = $false
        LogFile      = $logFile
        ErrorLogFile = $errorLogFile
        ProcessInfo  = $null
    }

    # bot.pid is only a hint. Reporting "not running" purely because the file
    # is missing is how a live bot went unnoticed: it kept rejoining the voice
    # channel while both this command and Stop-BATCRelayBot insisted it was
    # stopped. The processes themselves are the fallback.
    $botPid = $null

    if (Test-Path $pidFile) {
        $recorded = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)

        # Validate before use: Get-Process -Id throws a binding error on
        # anything non-numeric, so a truncated or garbled bot.pid used to take
        # the whole status command down instead of falling back.
        if ($recorded -match '^\s*\d+\s*$') {
            $candidate = [int]$recorded.Trim()
            if (Get-Process -Id $candidate -ErrorAction SilentlyContinue) {
                $botPid = $candidate
            }
        }
    }

    if (-not $botPid) {
        $found = @(Find-BotProcess -BotPath $BotPath)
        if ($found.Count -gt 0) {
            $botPid = $found[0]
            $status.OrphanedFromPidFile = $true
        }
    }

    if ($botPid) {
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
        if ($status.OrphanedFromPidFile) {
            Write-Host "  Note: found without a valid bot.pid - Stop-BATCRelayBot can still stop it." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Bot Status: NOT RUNNING" -ForegroundColor Yellow
    }

    Write-Host "  Output log: $($status.LogFile)" -ForegroundColor Cyan
    Write-Host "  Error log: $($status.ErrorLogFile)" -ForegroundColor Cyan

    return $status
}

