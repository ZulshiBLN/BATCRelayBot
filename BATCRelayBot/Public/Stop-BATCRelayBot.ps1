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
        # No bot, but a watcher: the bot ended and the watcher is in its
        # restart delay. Before this, "No running bot found" here was
        # followed ten seconds later by a bot nobody had asked for. The
        # signal is what the watcher waits for during that delay.
        $watchers = @(Find-BotWatcher -BotPath $BotPath)
        if ($watchers.Count -gt 0) {
            Write-Host "The bot is not running, but its watcher (PID $($watchers -join ', ')) is about to restart it - telling it not to..." -ForegroundColor Cyan
            $stopSignal = Join-Path $BotPath "stop.signal"
            New-Item -Path $stopSignal -ItemType File -Force -ErrorAction SilentlyContinue | Out-Null

            $deadline = (Get-Date).AddSeconds($Timeout)
            while ((Get-Date) -lt $deadline -and @(Find-BotWatcher -BotPath $BotPath).Count -gt 0) {
                Start-Sleep -Milliseconds 500
            }

            if (@(Find-BotWatcher -BotPath $BotPath).Count -gt 0) {
                # A bot may have come up in the meantime; it reads the same
                # signal. The watcher itself is ended so nothing follows.
                Stop-BotWatcher -BotPath $BotPath | Out-Null
                Stop-BotProcess -BotPath $BotPath -TimeoutSeconds $Timeout | Out-Null
                Write-Host "The watcher did not stop on its own and was ended." -ForegroundColor Yellow
            } else {
                Write-Host "The watcher has stopped; the bot will not be restarted." -ForegroundColor Green
            }
            Remove-Item $stopSignal -Force -ErrorAction SilentlyContinue
            Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
            return
        }

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

        # The watcher records the exit as -1, which is also what Task Manager
        # looks like. This line is what tells the two apart afterwards.
        Write-InstallLog -LogPath (Join-Path $BotPath "install.log") -Level WARN `
            -Message "Bot (PID $($running -join ', ')) did not respond to stop.signal within ${Timeout}s and was terminated by Stop-BATCRelayBot"

        # A terminated bot takes ffmpeg with it without closing the capture
        # it held on a VoiceMeeter bus, and VoiceMeeter's engine can be left
        # in a state where nothing on the machine plays audio. Restarting the
        # VoiceMeeter process does not clear it - the engine has to be
        # restarted, or VoiceMeeter shut down from its own tray menu.
        Write-Host ""
        Write-Host "  If audio stops working across the machine, restart VoiceMeeter's" -ForegroundColor Yellow
        Write-Host "  audio engine: right-click its tray icon > Restart Audio Engine." -ForegroundColor Yellow
        Write-Host "  Killing and relaunching the VoiceMeeter process does not fix it." -ForegroundColor Yellow
    }

    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}
