#Requires -Version 5.1

function Confirm-UninstallPrerequisites {
    <#
    .SYNOPSIS
    Validates that BATCRelayBot installation is in a state that can be safely uninstalled.

    .DESCRIPTION
    Phase 1 of uninstaller: Silently verify installation paths, detect running bot process,
    check file permissions, and return status. Runs with no prompts.

    .PARAMETER BotPath
    Installation directory to validate.
    Defaults to $env:USERPROFILE\AppData\Local\BATCRelayBot

    .OUTPUTS
    Hashtable with installation status:
    @{
        Valid = $true/$false              # Can uninstall proceed?
        InstallFound = $true/$false       # Installation directory exists?
        BotRunning = $true/$false         # Bot process currently running?
        ConfigPath = "full/path"          # Path to config.json
        LogPath = "full/path"             # Path to install.log
        Errors = @("error1", "error2")    # List of validation errors
    }

    .EXAMPLE
    $status = Confirm-UninstallPrerequisites
    if ($status.Valid) {
        Write-Host "Ready to uninstall"
    } else {
        Write-Host "Errors: $($status.Errors -join ', ')"
    }
    #>

    param(
        [string]$BotPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
    )

    $ErrorActionPreference = "SilentlyContinue"
    $errors = @()
    $installFound = $false
    $configPath = $null
    $logPath = $null
    $botRunning = $false

    # Step 1: Verify installation path exists
    if (-not (Test-Path $BotPath)) {
        $errors += "Installation directory not found: $BotPath"
    } else {
        $installFound = $true

        # Step 2: Verify critical files exist
        $configPath = Join-Path $BotPath "config.json"
        $logPath = Join-Path $BotPath "install.log"

        if (-not (Test-Path $configPath)) {
            $errors += "config.json not found at $configPath"
        }

        # Step 3: Check if bot process is running
        $botProcess = Get-Process python -ErrorAction SilentlyContinue |
                      Where-Object { $_.CommandLine -match "bot\.py" }

        if ($botProcess) {
            $botRunning = $true
            $errors += "Bot process is running (PID: $($botProcess.Id)). Stop it before uninstalling."
        }

        # Step 4: Verify file permissions (can we read/write?)
        try {
            $testFile = Join-Path $BotPath ".uninstall_test"
            "test" | Set-Content $testFile -ErrorAction Stop
            Remove-Item $testFile -ErrorAction Stop
        } catch {
            $errors += "Insufficient permissions to read/write in $BotPath"
        }
    }

    # Determine if we can proceed
    $valid = ($installFound -and -not $botRunning -and $errors.Count -eq 0)

    return @{
        Valid = $valid
        InstallFound = $installFound
        BotRunning = $botRunning
        InstallPath = $BotPath
        ConfigPath = $configPath
        LogPath = $logPath
        Errors = $errors
    }
}

Export-ModuleMember -Function Confirm-UninstallPrerequisites
