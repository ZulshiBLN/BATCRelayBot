#Requires -Version 5.1

<#
.SYNOPSIS
The process that outlives the bot, so that its death gets written down.

.DESCRIPTION
On 2026-09-13 the bot died around 22:28 and nothing recorded it: no traceback,
no "Stop signal detected", bot.pid still on disk. A healthy relay writes
nothing after "Audio stream started", so the log's last line was 21:46 and
meant nothing. TerminateProcess - Stop-Process -Force, Task Manager - runs no
Python at all, so nothing inside the process can ever record an outside kill.

The watcher can. Start-BATCRelayBot launches it hidden; it starts the bot,
keeps the handle, writes the child's pid to bot.pid, waits, and appends the
exit code and time to install.log. That file appends and survives restarts;
bot_error.log does not - -RedirectStandardError truncates it on every start,
which is why the watcher rotates the previous one aside first.

Exit codes seen on 2026-09-14: -1 for TerminateProcess, 1 for a Python
exception (traceback in bot_error.log), 0 for a clean exit. A native crash
reports its NTSTATUS.

Two of these are exported so the tests can drive a real watcher from outside
the module scope, the way Remove-BotContent is.
#>

function Invoke-BotWatcher {
    <#
    .SYNOPSIS
    Runs inside the watcher process: start the bot, wait, record the exit.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$BotPath,
        [Parameter(Mandatory = $true)][string]$Executable,
        [string]$Arguments = "bot.py",
        [int]$KeepLogs = 5
    )

    $logsDirectory = Join-Path $BotPath "logs"
    if (-not (Test-Path $logsDirectory)) {
        New-Item -ItemType Directory -Path $logsDirectory -Force | Out-Null
    }

    # Before the start, or the redirect below has already truncated the file
    # being rotated - and holds it open.
    $rotated = Invoke-BotLogRotation -LogsDirectory $logsDirectory -Keep $KeepLogs

    # bot.py's session header names the module version, and this is the only
    # process that knows it. Inherited by the child; nothing else reads it.
    $env:BATCRELAYBOT_MODULE_VERSION = Get-ModuleVersion

    $started = Get-Date
    $child = Start-Process `
        -FilePath $Executable `
        -ArgumentList $Arguments `
        -WorkingDirectory $BotPath `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logsDirectory "bot_output.log") `
        -RedirectStandardError (Join-Path $logsDirectory "bot_error.log") `
        -PassThru

    # PowerShell 5.1: without reading Handle before WaitForExit(), ExitCode
    # stays $null afterwards. Two watcher designs returned nothing before this
    # line was found.
    $null = $child.Handle

    $child.Id | Out-File -FilePath (Join-Path $BotPath "bot.pid") -Encoding ascii

    $kept = if ($rotated) { "; previous log kept as logs\$rotated" } else { "" }
    Write-InstallLog -LogPath (Join-Path $BotPath "install.log") -Level INFO `
        -Message "Bot started (PID $($child.Id)), watched by PID $PID$kept"

    $child.WaitForExit()

    Write-BotExitLine -BotPath $BotPath -ChildPid $child.Id -ExitCode $child.ExitCode -Started $started
}

function Write-BotExitLine {
    <#
    .SYNOPSIS
    One line in install.log saying how the bot ended - unless the bot is gone.

    .DESCRIPTION
    The uninstaller kills the child, which wakes the watcher to write into the
    directory being emptied - and Write-InstallLog would put install.log back,
    a leftover the removal created itself. The uninstaller ends the watcher
    first; this is the second guard for a watcher it did not find.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$BotPath,
        [Parameter(Mandatory = $true)][int]$ChildPid,
        [AllowNull()][object]$ExitCode,
        [Parameter(Mandatory = $true)][datetime]$Started
    )

    if (-not (Test-Path (Join-Path $BotPath "bot.py"))) { return }

    $elapsed = (Get-Date) - $Started
    $duration = "{0}h {1}m {2}s" -f [int]$elapsed.TotalHours, $elapsed.Minutes, $elapsed.Seconds

    if ($null -eq $ExitCode) {
        $code = "unknown"
        $meaning = "the exit code could not be read"
        $level = 'ERROR'
    } else {
        $code = [int]$ExitCode
        $meaning = Get-ExitCodeMeaning -ExitCode $code
        $level = switch ($code) { 0 { 'INFO' } -1 { 'WARN' } default { 'ERROR' } }
    }

    Write-InstallLog -LogPath (Join-Path $BotPath "install.log") -Level $level `
        -Message "Bot (PID $ChildPid) ended after $duration with exit code ${code}: $meaning"
}

function Get-ExitCodeMeaning {
    <#
    .SYNOPSIS
    What an exit code says about how the bot ended. Mirrored in README.md.
    #>
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][int]$ExitCode)

    switch ($ExitCode) {
        0  { return "clean exit" }
        1  { return "exited with an error - the traceback is in logs\bot_error.log" }
        -1 { return "terminated from outside (TerminateProcess) - Stop-BATCRelayBot, Task Manager or something else; no traceback exists" }
        -1073741510 { return "console closed or CTRL+C (0xC000013A)" }
        -1073741819 { return "native crash, access violation (0xC0000005) - see the faulthandler dump in logs\bot_error.log" }
    }

    if ($ExitCode -lt 0) {
        return ("native crash, NTSTATUS 0x{0:X8} - see logs\bot_error.log" -f $ExitCode)
    }
    return "exit code $ExitCode"
}

function Invoke-BotLogRotation {
    <#
    .SYNOPSIS
    Moves bot_error.log to a timestamped name and keeps the newest few.

    .DESCRIPTION
    Keep counts files in total, the one the next session writes included, so
    Keep 5 leaves four rotated logs behind. An empty log is not worth keeping.

    .OUTPUTS
    The rotated file's name, or $null when there was nothing to rotate.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$LogsDirectory,
        [int]$Keep = 5
    )

    $current = Join-Path $LogsDirectory "bot_error.log"
    $rotatedName = $null

    if ((Test-Path $current) -and (Get-Item $current).Length -gt 0) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $rotatedName = "bot_error.$stamp.log"
        $suffix = 0
        while (Test-Path (Join-Path $LogsDirectory $rotatedName)) {
            $suffix++
            $rotatedName = "bot_error.$stamp-$suffix.log"
        }
        try {
            Move-Item -Path $current -Destination (Join-Path $LogsDirectory $rotatedName) -ErrorAction Stop
        } catch {
            # A log that will not move is not worth failing the start over.
            $rotatedName = $null
        }
    }

    # Timestamped names sort chronologically.
    $rotated = @(Get-ChildItem -Path $LogsDirectory -Filter 'bot_error.*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object Name)
    $surplus = $rotated.Count - ($Keep - 1)
    if ($surplus -gt 0) {
        $rotated | Select-Object -First $surplus | ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    return $rotatedName
}

function Start-BotWatcher {
    <#
    .SYNOPSIS
    Launches a hidden watcher process for one installation.

    .DESCRIPTION
    A fresh powershell.exe has no module loaded and does not inherit a
    process-scope execution policy, so it is launched with -ExecutionPolicy
    Bypass and imports the module by path. -EncodedCommand carries the call:
    two levels of quoting around paths with spaces is how commands break.

    .OUTPUTS
    The watcher's Process object.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$BotPath,
        [Parameter(Mandatory = $true)][string]$Executable,
        [string]$Arguments = "bot.py",
        [string]$ModulePath = $MyInvocation.MyCommand.Module.Path
    )

    $quote = { param($s) "'" + ($s -replace "'", "''") + "'" }

    $command = @(
        "Import-Module $(& $quote $ModulePath) -Force -WarningAction SilentlyContinue",
        "& (Get-Module BATCRelayBot) { Invoke-BotWatcher -BotPath $(& $quote $BotPath) -Executable $(& $quote $Executable) -Arguments $(& $quote $Arguments) }"
    ) -join "; "

    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))

    Start-Process `
        -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded" `
        -WindowStyle Hidden `
        -PassThru
}

function Find-BotWatcher {
    <#
    .SYNOPSIS
    Finds the watcher process(es) for one installation.

    .DESCRIPTION
    The call is Base64 in the command line, so it is decoded and matched on
    the installation path. Find-BotProcess never sees these: it filters on
    python.exe and pythonw.exe before reading a command line.

    .OUTPUTS
    Array of process ids. Empty when nothing matches.
    #>
    [OutputType([int[]])]
    param([Parameter(Mandatory = $true)][string]$BotPath)

    $found = @()
    try {
        $processes = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop
    } catch {
        return $found
    }

    $needle = "-BotPath '" + ($BotPath.TrimEnd('\') -replace "'", "''") + "'"

    foreach ($process in $processes) {
        if ($process.CommandLine -notmatch '-EncodedCommand\s+([A-Za-z0-9+/=]+)') { continue }
        try {
            $decoded = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Matches[1]))
        } catch {
            continue
        }
        if ($decoded -notmatch 'Invoke-BotWatcher') { continue }
        if ($decoded.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        $found += [int]$process.ProcessId
    }

    return @($found | Select-Object -Unique)
}

function Stop-BotWatcher {
    <#
    .SYNOPSIS
    Ends the watcher without touching the bot.

    .DESCRIPTION
    For the uninstaller, which must silence the watcher before it stops the
    bot. Stop-BATCRelayBot does not call this: a watcher that records the
    exit is the point.

    .OUTPUTS
    The process ids that were ended.
    #>
    [OutputType([int[]])]
    param([Parameter(Mandatory = $true)][string]$BotPath)

    $watchers = @(Find-BotWatcher -BotPath $BotPath)
    foreach ($watcherPid in $watchers) {
        try { Stop-Process -Id $watcherPid -Force -ErrorAction Stop } catch {}
    }
    return $watchers
}

function Test-BotPidAlive {
    <#
    .SYNOPSIS
    Whether a pid names a running process started from the given executable.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)][string]$Executable
    )

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process) { return $false }
    return $process.Name -eq [System.IO.Path]::GetFileNameWithoutExtension($Executable)
}

Export-ModuleMember -Function @('Start-BotWatcher', 'Find-BotWatcher', 'Stop-BotWatcher')
