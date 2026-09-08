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

        # Overridable so the test suite does not deposit a timestamped log in
        # the developer's real roaming profile on every run - which is how
        # ninety-odd stray logs accumulated there.
        [string]$LogDirectory = (Join-Path $env:APPDATA "BATCRelayBot-Uninstall")
    )

    # The log lives outside the installation so it survives the deletion.
    $logDir = $LogDirectory
    New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue | Out-Null
    $logPath = Join-Path $logDir "removal-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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

    # ---- 3: remove the installation directory ---------------------------
    Write-Host "  [3/5] Removing the installation directory" -ForegroundColor Gray
    if (Test-Path $BotPath) {
        try {
            # Enumerate before deleting so the log and the summary can name
            # what went, not just how many.
            $doomed = @(Get-ChildItem -Path $BotPath -Recurse -File -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Name)

            Remove-Item $BotPath -Recurse -Force -ErrorAction Stop

            foreach ($name in $doomed) {
                if ($deletedFiles -notcontains $name) { $deletedFiles += $name }
            }
            "[OK] Removed $BotPath ($($doomed.Count) files)" | Add-Content $logPath -Encoding UTF8
            Write-Host "        Removed ($($doomed.Count) files)." -ForegroundColor Green
        } catch {
            $message = "Could not remove $($BotPath): $($_.Exception.Message)"
            $errors += $message
            "[ERROR] $message" | Add-Content $logPath -Encoding UTF8
            Write-Host "        FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "        Already gone." -ForegroundColor Gray
    }

    # ---- 4: roaming AppData leftovers -----------------------------------
    Write-Host "  [4/5] Cleaning up leftovers" -ForegroundColor Gray
    $appDataPath = Join-Path $env:APPDATA "BATCRelayBot"
    if (Test-Path $appDataPath) {
        try {
            Remove-Item $appDataPath -Recurse -Force -ErrorAction Stop
            "[OK] Removed $appDataPath" | Add-Content $logPath -Encoding UTF8
            Write-Host "        Removed $appDataPath" -ForegroundColor Green
        } catch {
            "[WARN] Could not remove $($appDataPath): $($_.Exception.Message)" | Add-Content $logPath -Encoding UTF8
            Write-Host "        WARNING: could not remove $appDataPath" -ForegroundColor Yellow
        }
    } else {
        Write-Host "        Nothing to clean up." -ForegroundColor Gray
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

    if ($DependencyChoices.RemoveModule) {
        Write-Host "        Removing the PowerShell module..." -ForegroundColor Gray
        try {
            Uninstall-Module BATCRelayBot -AllVersions -Force -ErrorAction Stop
            $removedDependencies += "BATCRelayBot module"
            "[OK] PowerShell module removed" | Add-Content $logPath -Encoding UTF8
            Write-Host "        Removed the PowerShell module." -ForegroundColor Green
        } catch {
            $message = "PowerShell module could not be removed: $($_.Exception.Message)"
            $errors += $message
            "[ERROR] $message" | Add-Content $logPath -Encoding UTF8
            Write-Host "        FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    $removedDependencies = @($removedDependencies | Where-Object { $_ })
    if ($removedDependencies.Count -eq 0) {
        Write-Host "        Nothing selected." -ForegroundColor Gray
    }

    $success = (-not (Test-Path $BotPath)) -and ($errors.Count -eq 0)

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
        Errors              = $errors
        LogPath             = $logPath
    }
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

Export-ModuleMember -Function @('Invoke-SecureUninstall', 'Remove-OptionalPackage')
