#Requires -Version 5.1

<#
.SYNOPSIS
Querying and removing winget packages, with verification.

.DESCRIPTION
Two mistakes made the old uninstaller unable to remove anything:

  winget show --id Gyan.FFmpeg   queries the *catalogue*, not the machine, so
                                 it succeeds for any package that exists at
                                 all - FFmpeg was offered for removal even
                                 when it had never been installed.

  winget uninstall "Python.Python"
                                 is not a real package id (the installed one
                                 is Python.Python.3.12), and because a native
                                 command does not throw, the surrounding
                                 try/catch never fired. The uninstaller
                                 reported success while nothing happened.

So: presence is decided by `winget list`, ids are read from what is actually
installed, and every removal is confirmed by querying again afterwards.
#>

function Test-WingetPresent {
    [OutputType([bool])]
    param()
    return [bool](Get-Command winget.exe -ErrorAction SilentlyContinue)
}

function Get-InstalledWingetPackage {
    <#
    .SYNOPSIS
    Returns the installed packages whose id matches a pattern.

    .PARAMETER IdPrefix
    Passed to `winget list --id`, which matches on substring.

    .PARAMETER IdPattern
    Regex the id must match, applied to winget's output. Matching the id
    rather than parsing columns keeps this independent of column widths and
    of the display language.

    .OUTPUTS
    Array of hashtables with Id and Version. Empty when nothing is installed.
    #>
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory = $true)][string]$IdPrefix,
        [Parameter(Mandatory = $true)][string]$IdPattern
    )

    $found = @()
    if (-not (Test-WingetPresent)) { return $found }

    try {
        $output = & winget.exe list --id $IdPrefix --accept-source-agreements 2>&1 |
            ForEach-Object { "$_" }
    } catch {
        return $found
    }

    # A non-zero exit means "no installed package found", which is an answer,
    # not a failure.
    if ($LASTEXITCODE -ne 0) { return $found }

    return (ConvertFrom-WingetListOutput -Lines $output -IdPattern $IdPattern)
}

function ConvertFrom-WingetListOutput {
    <#
    .SYNOPSIS
    Extracts package ids and versions from `winget list` output.

    .DESCRIPTION
    Matches the id by regex rather than splitting the table into columns:
    winget pads columns to the terminal width and localises the headers, so
    column positions are not dependable. Kept separate from the winget call so
    it can be tested against captured output.

    .OUTPUTS
    Array of hashtables with Id and Version.
    #>
    [OutputType([hashtable[]])]
    param(
        [string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$IdPattern
    )

    $found = @()
    $seen = @{}

    foreach ($line in $Lines) {
        if ($line -notmatch $IdPattern) { continue }

        $id = $Matches[0]
        if ($seen.ContainsKey($id)) { continue }

        # The version is the token following the id on the same row.
        $version = "unknown"
        if ($line -match ([regex]::Escape($id) + '\s+(\S+)')) {
            $version = $Matches[1]
        }

        $seen[$id] = $true
        $found += @{ Id = $id; Version = $version }
    }

    return $found
}

function Uninstall-WingetPackage {
    <#
    .SYNOPSIS
    Uninstalls one package by exact id and verifies it is gone.

    .DESCRIPTION
    winget's exit code is treated as advisory. What counts is whether the
    package still shows up afterwards, which is the only claim worth making
    to the user.

    .OUTPUTS
    Hashtable with Removed, ExitCode, Detail.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [string]$LogPath
    )

    if (-not (Test-WingetPresent)) {
        return @{ Removed = $false; ExitCode = $null; Detail = "winget is not available" }
    }

    try {
        $output = & winget.exe uninstall --id $Id --exact --silent `
            --accept-source-agreements --disable-interactivity 2>&1 |
            ForEach-Object { "$_" }
        $exitCode = $LASTEXITCODE
    } catch {
        return @{ Removed = $false; ExitCode = $null; Detail = $_.Exception.Message }
    }

    if ($LogPath) {
        foreach ($line in ($output | Select-Object -Last 8)) {
            "winget uninstall ${Id}: $line" | Add-Content $LogPath -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    }

    # Verify against the machine rather than trusting the exit code.
    $stillInstalled = @(Get-InstalledWingetPackage -IdPrefix $Id -IdPattern ([regex]::Escape($Id)))

    if ($stillInstalled.Count -eq 0) {
        return @{ Removed = $true; ExitCode = $exitCode; Detail = "verified removed" }
    }

    $detail = if ($exitCode -eq 0) {
        "winget reported success but the package is still installed"
    } else {
        $lastLine = ($output | Where-Object { $_ -match '\S' } | Select-Object -Last 1)
        "winget exit code $exitCode - $lastLine"
    }

    return @{ Removed = $false; ExitCode = $exitCode; Detail = $detail }
}

Export-ModuleMember -Function @(
    'Test-WingetPresent',
    'Get-InstalledWingetPackage',
    'ConvertFrom-WingetListOutput',
    'Uninstall-WingetPackage'
)
