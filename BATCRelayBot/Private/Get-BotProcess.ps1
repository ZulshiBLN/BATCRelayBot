#Requires -Version 5.1

<#
.SYNOPSIS
Finding and stopping the running bot process.

.DESCRIPTION
Shared by Stop-BATCRelayBot and the uninstaller so there is one way to answer
"is the bot running" and "stop it".

The detection deliberately does not use Get-Process: a Process object has no
CommandLine property on Windows PowerShell 5.1, so the previous
`Get-Process python | Where-Object { $_.CommandLine -match 'bot\.py' }`
silently matched nothing. The bot was therefore never detected as running and
never stopped - by the uninstaller either, which then deleted files out from
under a live process. Win32_Process does expose CommandLine on 5.1.

pythonw.exe matters as much as python.exe: Start-BATCRelayBot launches the
windowless variant.
#>

function Find-BotProcess {
    <#
    .SYNOPSIS
    Finds running bot.py processes belonging to one installation.

    .DESCRIPTION
    Matches this installation's own bot.py, so an unrelated Python program is
    never targeted, and neither is a directory that holds no bot at all.

    The one case it cannot separate is two installations both running a bare
    "bot.py" from their own working directory with no absolute path and no
    python_path to tell them apart.

    .OUTPUTS
    Array of process ids. Empty when nothing matches.
    #>
    [OutputType([int[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BotPath
    )

    $matchesFound = @()

    try {
        $processes = Get-CimInstance Win32_Process `
            -Filter "Name='python.exe' OR Name='pythonw.exe'" -ErrorAction Stop
    } catch {
        return $matchesFound
    }

    $normalisedBotPath = $BotPath.TrimEnd('\')

    foreach ($process in $processes) {
        if (-not $process.CommandLine) { continue }
        if ($process.CommandLine -notmatch 'bot\.py') { continue }

        # An absolute path in the command line is conclusive.
        if ($process.CommandLine -like "*$normalisedBotPath*") {
            $matchesFound += [int]$process.ProcessId
            continue
        }

        # Otherwise the command line is just "bot.py" and the installation
        # directory is the working directory, which Win32_Process does not
        # expose. Fall back to the executable path recorded in config.json.
        try {
            $configPath = Join-Path $normalisedBotPath "config.json"
            if (Test-Path $configPath) {
                $config = Get-Content $configPath -Raw -ErrorAction Stop | ConvertFrom-Json
                $expected = $config.python_path
                if ($expected) {
                    $expectedDir = Split-Path -Parent $expected
                    if ($process.ExecutablePath -and
                        (Split-Path -Parent $process.ExecutablePath) -eq $expectedDir) {
                        $matchesFound += [int]$process.ProcessId
                        continue
                    }
                }
            }
        } catch {}

        # Last resort: a bare "bot.py" command line, started with the
        # installation directory as its working directory, which
        # Win32_Process does not expose.
        #
        # Only for a path that actually holds a bot. Without that condition
        # this claimed any running bot.py for whatever path it was asked
        # about - so asking about an empty directory reported a bot there,
        # and the uninstaller and Stop-BATCRelayBot of one installation would
        # stop another one's process. It also made three tests depend on
        # whether a bot happened to be running on the machine.
        #
        # Two installations both running are still indistinguishable this way
        # when neither writes an absolute path; that needs the pid file, which
        # is what bot.pid is for.
        if (-not (Test-Path (Join-Path $normalisedBotPath 'bot.py'))) { continue }

        if ($process.CommandLine -match '(^|[\s"])bot\.py("|\s|$)') {
            $matchesFound += [int]$process.ProcessId
        }
    }

    return @($matchesFound | Select-Object -Unique)
}

function Stop-BotProcess {
    <#
    .SYNOPSIS
    Stops the bot, preferring the graceful path.

    .DESCRIPTION
    Writes stop.signal, which bot.py checks every second: it leaves the voice
    channel cleanly, closes the Discord connection and exits. Only if that
    does not happen within the timeout is the process terminated.

    Force-killing a connected voice client leaves the bot visibly stuck in the
    channel for a while, so the graceful path is always tried first.

    .OUTPUTS
    Hashtable with Stopped, Method, ProcessIds.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BotPath,

        [int]$TimeoutSeconds = 15
    )

    $running = @(Find-BotProcess -BotPath $BotPath)
    if ($running.Count -eq 0) {
        return @{ Stopped = $true; Method = 'not running'; ProcessIds = @() }
    }

    $stopSignal = Join-Path $BotPath "stop.signal"
    $signalWritten = $false

    if (Test-Path $BotPath) {
        try {
            New-Item -Path $stopSignal -ItemType File -Force -ErrorAction Stop | Out-Null
            $signalWritten = $true
        } catch {
            # Fall through to termination below.
        }
    }

    if ($signalWritten) {
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            if (@(Find-BotProcess -BotPath $BotPath).Count -eq 0) {
                Remove-Item $stopSignal -Force -ErrorAction SilentlyContinue
                return @{ Stopped = $true; Method = 'graceful'; ProcessIds = $running }
            }
            Start-Sleep -Milliseconds 500
        }
        Remove-Item $stopSignal -Force -ErrorAction SilentlyContinue
    }

    foreach ($processId in $running) {
        try {
            Stop-Process -Id $processId -Force -ErrorAction Stop
        } catch {}
    }

    $stillRunning = @(Find-BotProcess -BotPath $BotPath)

    return @{
        Stopped    = ($stillRunning.Count -eq 0)
        Method     = 'forced'
        ProcessIds = $running
    }
}

Export-ModuleMember -Function @('Find-BotProcess', 'Stop-BotProcess')
