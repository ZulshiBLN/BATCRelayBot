#Requires -Version 5.1

function Test-ModuleIsCurrent {
    <#
    .SYNOPSIS
    Is the module running this setup the newest one installed?

    .DESCRIPTION
    Update-Module installs the new version beside the old, while the
    PowerShell window keeps running the one it loaded. Install-BATCRelayBot
    typed in that window runs the old setup and copies the old bot.py - it
    happened twice on the day 1.6.1 shipped, once failing because the old
    folder was gone, once "succeeding" under a banner nobody read. The log
    named the source folder; nothing read that either.

    The check is a help, not a bar: when the comparison itself cannot be
    made - a module path out of reach, a version that cannot be read, a copy
    running from a checkout that PSModulePath knows nothing about - setup
    carries on with a warning. A setup that fails on its own help would be
    worse than the mistake it guards against.

    .OUTPUTS
    Hashtable: Current (bool), Running, Newest (versions or $null), and
    Warning when the comparison was not made.
    #>
    [OutputType([hashtable])]
    param([string]$LogPath)

    try {
        $runningText = Get-ModuleVersion
        $running = $null
        if (-not [version]::TryParse($runningText, [ref]$running)) {
            throw "the running version reads as '$runningText'"
        }

        $installed = @(Get-Module BATCRelayBot -ListAvailable -ErrorAction Stop |
            ForEach-Object { $_.Version } | Sort-Object -Descending)
        $newest = if ($installed.Count -gt 0) { [version]$installed[0] } else { $null }

        if ($newest -and $newest -gt $running) {
            return @{ Current = $false; Running = $running; Newest = $newest }
        }
        return @{ Current = $true; Running = $running; Newest = $newest }
    } catch {
        $reason = $_.Exception.Message
        Write-InstallLog "Could not compare module versions, continuing: $reason" -LogPath $LogPath -Level WARN
        return @{ Current = $true; Running = $null; Newest = $null; Warning = $reason }
    }
}

Export-ModuleMember -Function @('Test-ModuleIsCurrent')
