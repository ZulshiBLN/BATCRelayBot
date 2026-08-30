#Requires -Version 5.1

function Invoke-SecureUninstall {
    <#
    .SYNOPSIS
    Executes secure uninstallation (Phase 5).

    .DESCRIPTION
    Performs actual removal with secure file deletion.
    - Stops bot process if running
    - Securely deletes config.json (3-pass SDelete)
    - Deletes all other files
    - Cleans AppData
    - Optionally uninstalls dependencies
    - Comprehensive logging

    .PARAMETER BotPath
    Installation directory to remove.

    .PARAMETER DependencyChoices
    Hashtable with user's dependency removal choices.

    .OUTPUTS
    Hashtable with removal status:
    @{
        Success = $true/$false
        DeletedFiles = @(list)
        Errors = @(list)
        LogPath = path
    }
    #>

    param(
        [string]$BotPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot",
        [hashtable]$DependencyChoices = @{}
    )

    $logDir = "$env:APPDATA\BATCRelayBot-Uninstall"
    New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue | Out-Null
    $logPath = Join-Path $logDir "removal-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $deletedFiles = @()
    $errors = @()

    # Create removal log (saved to AppData so it survives directory deletion)
    "=== BATCRelayBot Removal Log ===" | Out-File $logPath -Force -Encoding UTF8NoBOM
    "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Add-Content $logPath -Encoding UTF8NoBOM -Encoding UTF8NoBOM
    ""  | Add-Content $logPath -Encoding UTF8NoBOM -Encoding UTF8NoBOM

    Write-Host ""
    Write-Host "Starting installation removal..." -ForegroundColor Green
    Write-Host ""

    # Step 1: Stop bot process
    Write-Host "[1/6] Stopping bot process..." -ForegroundColor Cyan
    try {
        $botProcess = Get-Process python -ErrorAction SilentlyContinue |
                      Where-Object { $_.CommandLine -match "bot\.py" }
        if ($botProcess) {
            Stop-Process $botProcess -Force -ErrorAction Stop
            "[OK] Bot process stopped" | Add-Content $logPath -Encoding UTF8NoBOM
            Write-Host "      DONE" -ForegroundColor Green
        } else {
            Write-Host "      (Not running)" -ForegroundColor Gray
        }
    } catch {
        $msg = "Warning: Could not stop bot process: $_"
        $msg | Add-Content $logPath -Encoding UTF8NoBOM
        Write-Host "      WARNING: $_" -ForegroundColor Yellow
    }
    Write-Host ""

    # Step 2: Secure delete config.json
    Write-Host "[2/6] Securely deleting config.json..." -ForegroundColor Cyan
    $configPath = Join-Path $BotPath "config.json"
    if (Test-Path $configPath) {
        try {
            # Try SDelete first (bundled with module)
            $sdeleteExe = Join-Path $PSScriptRoot "..\..\tools\sdelete64.exe"
            if (Test-Path $sdeleteExe) {
                & $sdeleteExe -p 3 $configPath 2>$null
                "[OK] config.json securely deleted (3-pass SDelete)" | Add-Content $logPath -Encoding UTF8NoBOM
                Write-Host "      DONE (SDelete)" -ForegroundColor Green
            } else {
                # Fallback: Multi-pass PowerShell overwrite
                $bytes = [byte[]]@(0) * (Get-Item $configPath).Length
                $random = New-Object Random
                for ($i = 0; $i -lt 3; $i++) {
                    $random.NextBytes($bytes)
                    [System.IO.File]::WriteAllBytes($configPath, $bytes)
                }
                Remove-Item $configPath -Force
                "[OK] config.json deleted (multi-pass overwrite)" | Add-Content $logPath -Encoding UTF8NoBOM
                Write-Host "      DONE (Multi-pass)" -ForegroundColor Green
            }
            $deletedFiles += "config.json"
        } catch {
            $msg = "ERROR: Failed to delete config.json: $_"
            $msg | Add-Content $logPath -Encoding UTF8NoBOM
            $errors += $msg
            Write-Host "      FAILED: $_" -ForegroundColor Red
        }
    }
    Write-Host ""

    # Step 3: Delete other files
    Write-Host "[3/6] Deleting installation files..." -ForegroundColor Cyan
    try {
        if (Test-Path $BotPath) {
            $files = Get-ChildItem -Path $BotPath -File -ErrorAction SilentlyContinue
            $count = 0
            foreach ($file in $files) {
                try {
                    Remove-Item $file.FullName -Force -ErrorAction Stop
                    $deletedFiles += $file.Name
                    $count++
                } catch {
                    $errors += "Could not delete $($file.Name): $_"
                }
            }
            "[OK] Deleted $count files from $BotPath" | Add-Content $logPath -Encoding UTF8NoBOM
            Write-Host "      DONE ($count files)" -ForegroundColor Green
        }
    } catch {
        $msg = "ERROR: Failed to delete files: $_"
        $msg | Add-Content $logPath -Encoding UTF8NoBOM
        $errors += $msg
        Write-Host "      FAILED: $_" -ForegroundColor Red
    }
    Write-Host ""

    # Step 4: Clean AppData
    Write-Host "[4/6] Cleaning AppData..." -ForegroundColor Cyan
    try {
        $appDataPath = "$env:APPDATA\BATCRelayBot"
        if (Test-Path $appDataPath) {
            Remove-Item $appDataPath -Recurse -Force -ErrorAction SilentlyContinue
            "[OK] Cleaned AppData\BATCRelayBot" | Add-Content $logPath -Encoding UTF8NoBOM
            Write-Host "      DONE" -ForegroundColor Green
        } else {
            Write-Host "      (No AppData folder)" -ForegroundColor Gray
        }

        $pipCache = "$env:APPDATA\pip\cache"
        if ((Test-Path $pipCache) -and $DependencyChoices.RemovePython) {
            Get-ChildItem -Path $pipCache -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
            "[OK] Cleaned pip cache" | Add-Content $logPath -Encoding UTF8NoBOM
        }
    } catch {
        Write-Host "      WARNING: $_" -ForegroundColor Yellow
    }
    Write-Host ""

    # Step 5: Uninstall optional dependencies
    Write-Host "[5/6] Uninstalling optional dependencies..." -ForegroundColor Cyan
    $depsRemoved = 0

    if ($DependencyChoices.RemovePython) {
        try {
            Write-Host "      Uninstalling Python..." -ForegroundColor Gray
            winget uninstall "Python.Python" --silent 2>$null
            "[OK] Python uninstalled" | Add-Content $logPath -Encoding UTF8NoBOM
            $depsRemoved++
        } catch {
            Write-Host "      WARNING: Python uninstall failed" -ForegroundColor Yellow
        }
    }

    if ($DependencyChoices.RemoveFFmpeg) {
        try {
            Write-Host "      Uninstalling FFmpeg..." -ForegroundColor Gray
            winget uninstall "Gyan.FFmpeg" --silent 2>$null
            "[OK] FFmpeg uninstalled" | Add-Content $logPath -Encoding UTF8NoBOM
            $depsRemoved++
        } catch {
            Write-Host "      WARNING: FFmpeg uninstall failed" -ForegroundColor Yellow
        }
    }

    if ($DependencyChoices.RemoveModule) {
        try {
            Write-Host "      Uninstalling PowerShell module..." -ForegroundColor Gray
            Uninstall-Module BATCRelayBot -Force -ErrorAction Stop
            "[OK] PowerShell module uninstalled" | Add-Content $logPath -Encoding UTF8NoBOM
            $depsRemoved++
        } catch {
            Write-Host "      WARNING: Module uninstall failed" -ForegroundColor Yellow
        }
    }

    if ($depsRemoved -eq 0) {
        Write-Host "      (No dependencies selected)" -ForegroundColor Gray
    } else {
        Write-Host "      DONE ($depsRemoved items removed)" -ForegroundColor Green
    }
    Write-Host ""

    # Write final verification BEFORE deleting directory (log is inside it)
    $success = -not (Test-Path $BotPath)
    if (-not $success) {
        "[OK] Pre-deletion verification: Installation directory exists, proceeding with removal" | Add-Content $logPath -Encoding UTF8NoBOM
    }

    # Step 6: Delete installation directory
    Write-Host "[6/6] Removing installation directory..." -ForegroundColor Cyan
    try {
        if (Test-Path $BotPath) {
            Remove-Item $BotPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "      DONE" -ForegroundColor Green
        }
    } catch {
        $msg = "ERROR: Could not remove directory: $_"
        $errors += $msg
        Write-Host "      FAILED: $_" -ForegroundColor Red
    }
    Write-Host ""

    # Verify removal (log file will be gone after directory deletion)
    $success = -not (Test-Path $BotPath)

    return @{
        Success = $success
        DeletedFiles = $deletedFiles
        Errors = $errors
        LogPath = $logPath
    }
}

Export-ModuleMember -Function Invoke-SecureUninstall
