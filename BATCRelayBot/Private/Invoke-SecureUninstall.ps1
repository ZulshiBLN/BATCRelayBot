#Requires -Version 5.1

<#
.SYNOPSIS
Performs the removal (uninstaller phase 5).

.DESCRIPTION
Every step reports what actually happened rather than what was attempted.
The previous version wrapped native winget calls in try/catch, which never
fires because native commands do not throw, so it logged "[OK] Python
uninstalled" regardless of the outcome.
#>

function Invoke-SecureUninstall {
    [OutputType([hashtable])]
    param(
        [string]$BotPath = (Join-Path $env:LOCALAPPDATA "BATCRelayBot"),
        [hashtable]$DependencyChoices = @{},

        # Overridable so the test suite writes its logs into its own sandbox.
        [string]$LogDirectory = $BotPath
    )

    # The log stays in the installation directory, which is emptied rather than
    # deleted. Writing it to a second folder under Roaming meant an uninstall
    # created a directory somewhere else in the profile while removing one here,
    # and left a timestamped file behind on every run.
    $logDir = $LogDirectory
    New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue | Out-Null
    $logPath = Join-Path $logDir "uninstall.log"

    $deletedFiles = @()
    $errors = @()
    $removedDependencies = @()

    @(
        "=== BATCRelayBot removal log ===",
        "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Target: $BotPath",
        ""
    ) | Out-File $logPath -Force -Encoding UTF8

    Write-Host ""

    # ---- 1: stop the bot ------------------------------------------------
    Write-Host "  [1/5] Stopping the bot" -ForegroundColor Gray
    try {
        $stopResult = Stop-BotProcess -BotPath $BotPath -TimeoutSeconds 15

        switch ($stopResult.Method) {
            'not running' {
                Write-Host "        Not running." -ForegroundColor Gray
                "[OK] No running bot process" | Add-Content $logPath -Encoding UTF8
            }
            'graceful' {
                Write-Host "        Stopped cleanly (left the voice channel)." -ForegroundColor Green
                "[OK] Bot stopped gracefully (PIDs: $($stopResult.ProcessIds -join ', '))" | Add-Content $logPath -Encoding UTF8
            }
            'forced' {
                if ($stopResult.Stopped) {
                    Write-Host "        Did not respond in time - terminated." -ForegroundColor Yellow
                    "[WARN] Bot force-terminated (PIDs: $($stopResult.ProcessIds -join ', '))" | Add-Content $logPath -Encoding UTF8
                } else {
                    $message = "Bot process could not be stopped (PIDs: $($stopResult.ProcessIds -join ', '))"
                    $errors += $message
                    "[ERROR] $message" | Add-Content $logPath -Encoding UTF8
                    Write-Host "        FAILED - files may stay locked." -ForegroundColor Red
                }
            }
        }
    } catch {
        $message = "Stopping the bot failed: $($_.Exception.Message)"
        $errors += $message
        "[ERROR] $message" | Add-Content $logPath -Encoding UTF8
        Write-Host "        WARNING: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # ---- 2: overwrite and delete config.json ----------------------------
    Write-Host "  [2/5] Removing config.json" -ForegroundColor Gray
    $configPath = Join-Path $BotPath "config.json"
    if (Test-Path $configPath) {
        try {
            # Overwrite before deleting. On an SSD this does not guarantee the
            # old bytes are unreachable - wear levelling may keep them - so it
            # is described as overwriting, not as secure erasure, and the user
            # is told to reset the token instead.
            $length = (Get-Item $configPath).Length
            if ($length -gt 0) {
                $buffer = New-Object byte[] $length
                $random = New-Object System.Random
                for ($pass = 0; $pass -lt 3; $pass++) {
                    $random.NextBytes($buffer)
                    [System.IO.File]::WriteAllBytes($configPath, $buffer)
                }
            }
            Remove-Item $configPath -Force -ErrorAction Stop
            $deletedFiles += "config.json"
            "[OK] config.json overwritten (3 passes) and deleted" | Add-Content $logPath -Encoding UTF8
            Write-Host "        Overwritten and deleted." -ForegroundColor Green
        } catch {
            $message = "config.json could not be removed: $($_.Exception.Message)"
            $errors += $message
            "[ERROR] $message" | Add-Content $logPath -Encoding UTF8
            Write-Host "        FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "        Not present." -ForegroundColor Gray
    }

    # ---- 3: remove the installed files -----------------------------------
    Write-Host "  [3/5] Removing the installed files" -ForegroundColor Gray
    $removal = Remove-BotContent -BotPath $BotPath -Keep (Split-Path $logPath -Leaf) -LogPath $logPath

    foreach ($name in $removal.Deleted) {
        if ($deletedFiles -notcontains $name) { $deletedFiles += $name }
    }

    if ($removal.Blocked.Count -eq 0) {
        $count = $removal.Deleted.Count
        Write-Host "        Removed $count file$(if ($count -ne 1) { 's' })." -ForegroundColor Green
    } else {
        foreach ($item in $removal.Blocked) {
            $message = "Could not remove $($item.Path): $($item.Reason)"
            $errors += $message
            "[ERROR] $message" | Add-Content $logPath -Encoding UTF8
            Write-Host "        FAILED: $($item.Path)" -ForegroundColor Red
            Write-Host "                $($item.Reason)" -ForegroundColor Red
        }
    }

    # ---- 4: what is left --------------------------------------------------
    Write-Host "  [4/5] Checking what is left" -ForegroundColor Gray

    $leftovers = @()
    if (Test-Path $BotPath) {
        $leftovers = @(Get-ChildItem -Path $BotPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $logPath } |
            Select-Object -ExpandProperty FullName)
    }

    # Older versions kept state in the first of these and wrote their removal
    # log into the second, so an uninstall used to create a folder elsewhere in
    # the profile while removing one here.
    foreach ($stale in @((Join-Path $env:APPDATA "BATCRelayBot"),
                         (Join-Path $env:APPDATA "BATCRelayBot-Uninstall"))) {
        if (-not (Test-Path $stale)) { continue }
        try {
            Remove-Item $stale -Recurse -Force -ErrorAction Stop
            "[OK] Removed $stale" | Add-Content $logPath -Encoding UTF8
            Write-Host "        Removed $stale" -ForegroundColor Green
        } catch {
            $leftovers += $stale
            "[WARN] Could not remove $($stale): $($_.Exception.Message)" | Add-Content $logPath -Encoding UTF8
        }
    }

    # This step used to look only at Roaming, so it printed "Nothing to clean
    # up" directly underneath a step 3 that had just failed on a locked file.
    # A failure that announces itself as tidy is worse than the failure.
    if ($leftovers.Count -eq 0) {
        Write-Host "        Nothing left behind." -ForegroundColor Green
    } else {
        Write-Host "        Still present:" -ForegroundColor Yellow
        foreach ($item in $leftovers) {
            Write-Host "          $item" -ForegroundColor Yellow
        }
    }

    # ---- 5: optional components -----------------------------------------
    Write-Host "  [5/5] Optional components" -ForegroundColor Gray

    if ($DependencyChoices.RemovePython) {
        foreach ($package in @($DependencyChoices.PythonPackages)) {
            $removedDependencies += (Remove-OptionalPackage -Package $package -Label "Python" `
                -LogPath $logPath -ErrorList ([ref]$errors))
        }
    }

    if ($DependencyChoices.RemoveFFmpeg) {
        foreach ($package in @($DependencyChoices.FFmpegPackages)) {
            $removedDependencies += (Remove-OptionalPackage -Package $package -Label "FFmpeg" `
                -LogPath $logPath -ErrorList ([ref]$errors))
        }
    }

    $removedDependencies = @($removedDependencies | Where-Object { $_ })
    if ($removedDependencies.Count -eq 0) {
        Write-Host "        None selected." -ForegroundColor Gray
    }

    # The directory itself survives, holding this log and nothing else, so
    # "gone" is decided by what is left inside it rather than by its absence.
    $success = ($errors.Count -eq 0) -and ($leftovers.Count -eq 0)

    @(
        "",
        "Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Success: $success",
        "Errors: $($errors.Count)"
    ) | Add-Content $logPath -Encoding UTF8

    return @{
        Success             = $success
        DeletedFiles        = $deletedFiles
        RemovedDependencies = $removedDependencies
        Leftovers           = $leftovers
        Errors              = $errors
        LogPath             = $logPath
    }
}

function Remove-BotContent {
    <#
    .SYNOPSIS
    Empties the installation directory, keeping one file, and reports what
    would not go.

    .DESCRIPTION
    A file handle outlives the process that held it by a moment. Stopping the
    bot and deleting immediately afterwards failed on bot_error.log with "used
    by another process" - the bot had exited, Windows had not yet let go. One
    attempt was therefore enough to fail while being nowhere near enough to
    succeed, so this retries a few times before giving up.

    It deletes the contents rather than the directory: the removal log lives
    there and has to survive the removal it is describing.

    .OUTPUTS
    Hashtable with Deleted (file names) and Blocked (Path and Reason each).
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][string]$BotPath,
        [Parameter(Mandatory = $true)][string]$Keep,
        [string]$LogPath,
        [int]$Attempts = 5,
        [int]$WaitMilliseconds = 1000
    )

    if (-not (Test-Path $BotPath)) {
        return @{ Deleted = @(); Blocked = @() }
    }

    $doomed = @(Get-ChildItem -Path $BotPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne $Keep } |
        Select-Object -ExpandProperty Name)

    $blocked = @()
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $blocked = @()

        foreach ($item in Get-ChildItem -Path $BotPath -Force -ErrorAction SilentlyContinue) {
            if ($item.Name -eq $Keep) { continue }
            try {
                Remove-Item $item.FullName -Recurse -Force -ErrorAction Stop
            } catch {
                $blocked += @{ Path = $item.FullName; Reason = $_.Exception.Message }
            }
        }

        if ($blocked.Count -eq 0) { break }

        if ($attempt -lt $Attempts) {
            if ($LogPath) {
                "[WARN] $($blocked.Count) item(s) still locked, attempt $attempt of $Attempts" |
                    Add-Content $LogPath -Encoding UTF8
            }
            Start-Sleep -Milliseconds $WaitMilliseconds
        }
    }

    $stillThere = @(Get-ChildItem -Path $BotPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne $Keep } |
        Select-Object -ExpandProperty Name)

    $deleted = @($doomed | Where-Object { $stillThere -notcontains $_ })

    if ($LogPath) {
        "[OK] Removed $($deleted.Count) file(s) from $BotPath" | Add-Content $LogPath -Encoding UTF8
    }

    return @{ Deleted = $deleted; Blocked = $blocked }
}

function Remove-OptionalPackage {
    <#
    .SYNOPSIS
    Removes one winget package and reports the verified outcome.

    .OUTPUTS
    A description of what was removed, or $null when it was not.
    #>
    [OutputType([string])]
    param(
        [hashtable]$Package,
        [string]$Label,
        [string]$LogPath,
        [ref]$ErrorList
    )

    if (-not $Package -or -not $Package.Id) { return $null }

    Write-Host "        Removing $Label ($($Package.Id))..." -ForegroundColor Gray
    $result = Uninstall-WingetPackage -Id $Package.Id -LogPath $LogPath

    if ($result.Removed) {
        "[OK] $Label removed: $($Package.Id)" | Add-Content $LogPath -Encoding UTF8
        Write-Host "        Removed $Label." -ForegroundColor Green
        return "$Label ($($Package.Id))"
    }

    $message = "$Label ($($Package.Id)) was not removed: $($result.Detail)"
    $ErrorList.Value += $message
    "[ERROR] $message" | Add-Content $LogPath -Encoding UTF8
    Write-Host "        FAILED: $($result.Detail)" -ForegroundColor Red
    Write-Host "        Remove it manually with: winget uninstall --id $($Package.Id) --exact" -ForegroundColor Yellow
    return $null
}

Export-ModuleMember -Function @('Invoke-SecureUninstall', 'Remove-OptionalPackage', 'Remove-BotContent')
