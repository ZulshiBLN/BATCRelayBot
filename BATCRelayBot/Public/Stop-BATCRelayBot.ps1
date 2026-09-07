function Stop-BATCRelayBot {
    <#
    .SYNOPSIS
    Cleanly stops the BATC Relay Bot.

    .DESCRIPTION
    Signals the bot to leave the voice channel gracefully and exit.
    Falls back to force-kill if graceful shutdown times out.

    .PARAMETER BotPath
    Path to the bot installation directory.
    Defaults to $env:USERPROFILE\AppData\Local\BATCRelayBot

    .PARAMETER Timeout
    Seconds to wait for graceful shutdown before force-killing (default: 15).

    .EXAMPLE
    Stop-BATCRelayBot

    .EXAMPLE
    Stop-BATCRelayBot -BotPath "D:\MyBot\BATCRelayBot" -Timeout 20
    #>

    param(
        [string]$BotPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot",
        [int]$Timeout = 15
    )

    $pidFile = Join-Path $BotPath "bot.pid"
    $stopSignalFile = Join-Path $BotPath "stop.signal"

    # bot.pid is a hint, not the authority. Trusting it exclusively is how a
    # running bot got orphaned: a stale PID made this function delete the file
    # and report "not running", after which every later call said the same
    # while the real process kept rejoining the voice channel with no way left
    # to stop it. The process itself is therefore always the fallback.
    $botPid = $null

    if (Test-Path $pidFile) {
        $recorded = (Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($recorded -and (Get-Process -Id $recorded -ErrorAction SilentlyContinue)) {
            $botPid = [int]$recorded
        } else {
            Write-Host "bot.pid refers to PID $recorded, which is not running - searching for the bot process..." -ForegroundColor Yellow
        }
    }

    if (-not $botPid) {
        $found = Find-BotProcess -BotPath $BotPath
        if ($found) {
            $botPid = $found
            Write-Host "Found a running bot process (PID $botPid) without a valid bot.pid." -ForegroundColor Yellow
        }
    }

    if (-not $botPid) {
        Write-Host "No running bot found for $BotPath." -ForegroundColor Yellow
        Remove-Item $pidFile -ErrorAction SilentlyContinue
        return
    }

    Write-Host "Sending stop signal to bot (PID $botPid) - waiting for graceful shutdown..." -ForegroundColor Cyan
    New-Item -Path $stopSignalFile -ItemType File -Force | Out-Null

    $waited = 0
    while ((Get-Process -Id $botPid -ErrorAction SilentlyContinue) -and $waited -lt $Timeout) {
        Start-Sleep -Seconds 1
        $waited++
    }

    if (Get-Process -Id $botPid -ErrorAction SilentlyContinue) {
        Write-Host "Bot did not shut down cleanly in time - force-stopping..." -ForegroundColor Yellow
        Stop-Process -Id $botPid -Force
        Write-Host "Bot force-stopped." -ForegroundColor Yellow
    } else {
        Write-Host "Bot shut down cleanly (after $waited second(s))." -ForegroundColor Green
    }

    Remove-Item $pidFile -ErrorAction SilentlyContinue
    Remove-Item $stopSignalFile -ErrorAction SilentlyContinue
}

function Find-BotProcess {
    <#
    .SYNOPSIS
    Finds a running bot.py process belonging to this installation.

    .DESCRIPTION
    Matches on the executable's own bot.py rather than on any python process,
    so an unrelated Python program is never targeted. Used when bot.pid is
    missing or stale.

    .OUTPUTS
    The process id, or $null when no matching process is running.
    #>
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BotPath
    )

    try {
        $processes = Get-CimInstance Win32_Process `
            -Filter "Name='python.exe' OR Name='pythonw.exe'" -ErrorAction Stop
    } catch {
        return $null
    }

    foreach ($process in $processes) {
        if ($process.CommandLine -notmatch 'bot\.py') { continue }

        # The command line is usually just "bot.py" with the install directory
        # as the working directory, so confirm via the executable path or an
        # absolute path in the command line.
        if ($process.CommandLine -like "*$BotPath*") { return [int]$process.ProcessId }

        try {
            $owner = Get-Process -Id $process.ProcessId -ErrorAction Stop
            if ($owner.Path -and (Test-Path (Join-Path $BotPath "bot.py"))) {
                return [int]$process.ProcessId
            }
        } catch {}
    }

    return $null
}

