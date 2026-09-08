function Stop-BATCRelayBot {
    <#
    .SYNOPSIS
    Cleanly stops the BATC Relay Bot.

    .DESCRIPTION
    Signals the bot to leave the voice channel gracefully and exit.
    Falls back to force-kill if graceful shutdown times out.

    .PARAMETER BotPath
    Path to the bot installation directory.
    Defaults to $env:LOCALAPPDATA\BATCRelayBot

    .PARAMETER Timeout
    Seconds to wait for graceful shutdown before force-killing (default: 15).

    .EXAMPLE
    Stop-BATCRelayBot

    .EXAMPLE
    Stop-BATCRelayBot -BotPath "D:\MyBot\BATCRelayBot" -Timeout 20
    #>

    param(
        [string]$BotPath = (Join-Path $env:LOCALAPPDATA "BATCRelayBot"),
        [int]$Timeout = 15
    )

    $pidFile = Join-Path $BotPath "bot.pid"

    # bot.pid is a hint, not the authority. Trusting it exclusively is how a
    # running bot got orphaned: a stale PID made this function delete the file
    # and report "not running", after which every later call said the same
    # while the real process kept rejoining the voice channel with no way left
    # to stop it. Stop-BotProcess always looks at the actual processes.
    $running = @(Find-BotProcess -BotPath $BotPath)

    if ($running.Count -eq 0) {
        Write-Host "No running bot found for $BotPath." -ForegroundColor Yellow
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        return
    }

    Write-Host "Stopping the bot (PID $($running -join ', ')) - waiting for it to leave the channel..." -ForegroundColor Cyan
    $result = Stop-BotProcess -BotPath $BotPath -TimeoutSeconds $Timeout

    if (-not $result.Stopped) {
        Write-Host "The bot could not be stopped. Try again, or end the process manually." -ForegroundColor Red
        return
    }

    if ($result.Method -eq 'graceful') {
        Write-Host "Bot shut down cleanly." -ForegroundColor Green
    } else {
        Write-Host "Bot did not respond in time and was terminated." -ForegroundColor Yellow
    }

    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}
