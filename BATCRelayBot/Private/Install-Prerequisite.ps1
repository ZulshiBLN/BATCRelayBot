#Requires -Version 5.1

<#
.SYNOPSIS
Installs missing tools via winget and re-detects them afterwards.

.DESCRIPTION
The re-detection is the entire point. Before 1.4.0 the Phase 4b handler ran
winget and then returned without touching the prerequisites hashtable, so the
readiness check that followed still saw Found=$false and refused to install -
even though the tool had just been installed successfully. A second, working
copy of this logic sat unreachable inside Start-Installation.

There is now exactly one implementation, and "did it work" is answered by
detection rather than by winget's exit code, which reports failure for
harmless cases such as the package already being present.
#>

function Test-WingetAvailable {
    [OutputType([bool])]
    param()
    return [bool](Get-Command winget.exe -ErrorAction SilentlyContinue)
}

function Invoke-WingetInstall {
    <#
    .SYNOPSIS
    Installs one winget package, preferring the per-user scope.

    .DESCRIPTION
    User scope avoids the UAC prompt and keeps the install inside the profile,
    which is what this module needs - it never requires admin rights. Not every
    package supports --scope user, so a scoped failure retries unscoped.

    .OUTPUTS
    Hashtable with ExitCode and Scope. Exit codes are advisory only.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [string]$LogPath
    )

    $commonArgs = @(
        'install', '--id', $PackageId, '--exact', '--silent',
        '--accept-package-agreements', '--accept-source-agreements'
    )

    Write-InstallLog "winget install $PackageId --scope user" -LogPath $LogPath
    $output = & winget.exe @commonArgs --scope user 2>&1 | ForEach-Object { "$_" }
    $exitCode = $LASTEXITCODE
    Write-InstallLog "winget (user scope) exit code $exitCode" -LogPath $LogPath

    if ($exitCode -ne 0) {
        # Log sanitised: winget echoes URLs and occasionally environment data.
        foreach ($line in ($output | Select-Object -Last 5)) {
            Write-InstallLog "winget: $line" -LogPath $LogPath -Level WARN
        }

        Write-InstallLog "Retrying $PackageId without an explicit scope" -LogPath $LogPath
        $output = & winget.exe @commonArgs 2>&1 | ForEach-Object { "$_" }
        $exitCode = $LASTEXITCODE
        Write-InstallLog "winget (default scope) exit code $exitCode" -LogPath $LogPath

        return @{ ExitCode = $exitCode; Scope = 'default' }
    }

    return @{ ExitCode = $exitCode; Scope = 'user' }
}

function Install-MissingPrerequisite {
    <#
    .SYNOPSIS
    Installs Python and/or FFmpeg if missing, then re-detects both.

    .PARAMETER Prerequisites
    The detection results. Returned updated - callers must use the return
    value rather than relying on the argument being mutated.

    .OUTPUTS
    The updated prerequisites hashtable.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Prerequisites,
        [string]$LogPath
    )

    if (-not (Test-WingetAvailable)) {
        Write-Host "  winget is not available on this system." -ForegroundColor Red
        Write-Host "  Install 'App Installer' from the Microsoft Store, or install the" -ForegroundColor Yellow
        Write-Host "  missing tools manually and run the installer again." -ForegroundColor Yellow
        Write-InstallLog "winget not available - cannot auto-install" -LogPath $LogPath -Level ERROR
        return $Prerequisites
    }

    $targets = @()
    if (-not $Prerequisites.Python.Found) {
        $targets += @{ Name = 'Python 3.12'; PackageId = 'Python.Python.3.12'; Key = 'Python' }
    }
    if (-not $Prerequisites.FFmpeg.Found) {
        $targets += @{ Name = 'FFmpeg'; PackageId = 'Gyan.FFmpeg'; Key = 'FFmpeg' }
    }

    foreach ($target in $targets) {
        Write-Host "  Installing $($target.Name) via winget..." -ForegroundColor Gray
        $result = Invoke-WingetInstall -PackageId $target.PackageId -LogPath $LogPath

        if ($result.ExitCode -ne 0) {
            # Not fatal yet: winget reports non-zero when the package is
            # already installed, so let detection have the final word.
            Write-Host "  winget reported exit code $($result.ExitCode) - verifying anyway..." -ForegroundColor Yellow
        }
    }

    if ($targets.Count -eq 0) { return $Prerequisites }

    # winget updates the persisted PATH, not the one this process inherited.
    Update-ProcessPath

    Write-Host "  Re-checking..." -ForegroundColor Gray
    $updated = @{}
    foreach ($key in $Prerequisites.Keys) { $updated[$key] = $Prerequisites[$key] }

    foreach ($target in $targets) {
        $detected = switch ($target.Key) {
            'Python' { Find-Python }
            'FFmpeg' { Find-FFmpeg }
        }
        $updated[$target.Key] = $detected

        if ($detected.Found) {
            Write-Host "  OK  $($target.Name): $($detected.Path)" -ForegroundColor Green
            Write-InstallLog "$($target.Name) installed and verified at $($detected.Path)" -LogPath $LogPath
        } else {
            Write-Host "  --  $($target.Name) still not detected: $($detected.Reason)" -ForegroundColor Red
            Write-InstallLog "$($target.Name) still not detected after install: $($detected.Reason)" -LogPath $LogPath -Level ERROR
        }
    }

    Write-Host ""
    return $updated
}

function Update-ProcessPath {
    <#
    .SYNOPSIS
    Rebuilds $env:PATH from the machine and user environment.

    .DESCRIPTION
    A freshly installed tool is only on the PATH of processes started after
    the install, so without this the current session keeps missing it.
    #>
    param()

    try {
        $machine = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
        $user = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
        $env:PATH = (@($machine, $user) | Where-Object { $_ }) -join ';'
    } catch {
        # Keep the inherited PATH; detection has filesystem fallbacks anyway.
    }
}

Export-ModuleMember -Function @(
    'Install-MissingPrerequisite',
    'Invoke-WingetInstall',
    'Test-WingetAvailable',
    'Update-ProcessPath'
)
