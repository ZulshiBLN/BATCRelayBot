#Requires -Version 5.1

<#
.SYNOPSIS
Checks what state the installation is in (uninstaller phase 1). No prompts.

.DESCRIPTION
Only one thing is fatal: there is nothing at the path to remove. Everything
else is reported and handled.

A missing config.json used to abort the whole uninstall, which meant the
uninstaller refused exactly the case it is most needed for - a half-finished
or partly deleted installation. A running bot used to abort it too, but was
never actually detected, so the check only ever got in the way.
#>

function Confirm-UninstallPrerequisites {
    [OutputType([hashtable])]
    param(
        [string]$BotPath = (Join-Path $env:LOCALAPPDATA "BATCRelayBot")
    )

    $errors = @()
    $warnings = @()
    $configPath = Join-Path $BotPath "config.json"
    $logPath = Join-Path $BotPath "install.log"
    $runningProcesses = @()

    $installFound = Test-Path $BotPath

    if (-not $installFound) {
        $errors += "Nothing to remove - $BotPath does not exist."
    } else {
        # A file where the directory should be: exactly what a botched copy
        # leaves behind, and it blocks a reinstall until it is gone.
        $item = Get-Item $BotPath -Force -ErrorAction SilentlyContinue
        if ($item -and -not $item.PSIsContainer) {
            $warnings += "$BotPath is a file, not a directory - it will be removed."
        } else {
            if (-not (Test-Path $configPath)) {
                $warnings += "config.json is missing - the installation is incomplete and will be cleaned up."
            }

            try {
                $probe = Join-Path $BotPath ".uninstall_probe"
                "probe" | Set-Content $probe -ErrorAction Stop
                Remove-Item $probe -Force -ErrorAction Stop
            } catch {
                $errors += "No write access to $BotPath - run PowerShell as the user who installed it."
            }
        }

        $runningProcesses = @(Find-BotProcess -BotPath $BotPath)
        if ($runningProcesses.Count -gt 0) {
            # Not an error: the removal step stops it before deleting anything.
            $warnings += "The bot is running (PID $($runningProcesses -join ', ')) and will be stopped."
        }
    }

    return @{
        Valid          = ($installFound -and $errors.Count -eq 0)
        InstallFound   = $installFound
        BotRunning     = ($runningProcesses.Count -gt 0)
        BotProcessIds  = $runningProcesses
        InstallPath    = $BotPath
        ConfigPath     = $configPath
        LogPath        = $logPath
        Warnings       = $warnings
        Errors         = $errors
    }
}

Export-ModuleMember -Function Confirm-UninstallPrerequisites
