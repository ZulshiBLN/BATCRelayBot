function Stop-BATCRelayBot {
    <#
    .SYNOPSIS
    Cleanly stops the BATC Relay Bot.

    .DESCRIPTION
    Signals the bot to leave the voice channel gracefully and exit.
    Falls back to force-kill if graceful shutdown times out.

    .PARAMETER ProjectPath
    Path to the project directory. Defaults to the current directory.

    .PARAMETER Timeout
    Seconds to wait for graceful shutdown before force-killing (default: 15).

    .EXAMPLE
    Stop-BATCRelayBot
    Stop-BATCRelayBot -ProjectPath "C:\MyProjects\ATC-Relay-Bot" -Timeout 20
    #>

    param(
        [string]$ProjectPath = (Get-Location).Path,
        [int]$Timeout = 15
    )

    $pidFile = Join-Path $ProjectPath "bot.pid"
    $stopSignalFile = Join-Path $ProjectPath "stop.signal"

    if (-not (Test-Path $pidFile)) {
        Write-Host "No bot.pid found - bot is not running or was not started with Start-BATCRelayBot." -ForegroundColor Yellow
        exit 0
    }

    $botPid = Get-Content $pidFile -ErrorAction SilentlyContinue

    if (-not ($botPid -and (Get-Process -Id $botPid -ErrorAction SilentlyContinue))) {
        Write-Host "Process PID $botPid is not running." -ForegroundColor Yellow
        Remove-Item $pidFile -ErrorAction SilentlyContinue
        exit 0
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

