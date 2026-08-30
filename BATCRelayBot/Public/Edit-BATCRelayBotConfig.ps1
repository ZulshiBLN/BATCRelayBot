function Edit-BATCRelayBotConfig {
    <#
    .SYNOPSIS
    Interactive configuration editor for BATCRelayBot.

    .DESCRIPTION
    Allows users to modify specific config fields (token, channel, format, activity)
    without re-running the full installer. Validates, backs up, and safely saves changes.

    .PARAMETER InstallPath
    Path to BATCRelayBot installation (default: $env:USERPROFILE\AppData\Local\BATCRelayBot)

    .OUTPUTS
    Hashtable with properties:
    - Success (bool): Operation succeeded
    - BackupPath (string): Path to created backup
    - UpdatedFields (hashtable): Fields that were changed
    - Errors (array): Any errors encountered
    - LogPath (string): Path to operation log

    .EXAMPLE
    $result = Edit-BATCRelayBotConfig
    if ($result.Success) {
        Write-Host "Configuration updated successfully"
        Write-Host "Backup: $($result.BackupPath)"
    }
    #>

    param(
        [string]$InstallPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
    )

    # Feature disabled for v1.3.10 - critical bugs identified during audit
    # See plans/todo/CONFIG-EDITOR-BUGS-ANALYSIS.md for details
    # Will be fully implemented in v1.3.11
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host "  Edit-BATCRelayBotConfig is not yet available in v1.3.10      " -ForegroundColor Yellow
    Write-Host "  This feature has critical bugs and will be fixed in v1.3.11   " -ForegroundColor Yellow
    Write-Host "  For now, edit config.json manually or wait for the next       " -ForegroundColor Yellow
    Write-Host "  release.                                                      " -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host ""

    return @{
        Success = $false
        Message = "Edit-BATCRelayBotConfig is not yet available in this version"
        BackupPath = $null
        UpdatedFields = @{}
        Errors = @("Feature disabled for v1.3.10 - will be implemented in v1.3.11")
        LogPath = $null
    }

    # Phase 1: Validate Prerequisites
    Write-Host "Checking prerequisites..." -ForegroundColor Cyan
    $prereq = Confirm-ConfigEditorPrerequisites -InstallPath $InstallPath

    if (-not $prereq.Valid) {
        Write-Host "Prerequisites check failed:" -ForegroundColor Red
        $prereq.Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }

        return @{
            Success       = $false
            BackupPath    = $null
            UpdatedFields = @{}
            Errors        = $prereq.Errors
            LogPath       = $null
        }
    }

    if ($prereq.BotRunning) {
        Write-Host "Bot is currently running. Changes will take effect after restart." -ForegroundColor Yellow
        Read-Host "Press Enter to continue"
    }

    # Phase 2: Show Menu & Get User Selection
    Write-Host ""
    $menuResult = Show-ConfigEditorMenu -ConfigPath $prereq.ConfigPath

    if ($null -eq $menuResult) {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        return @{
            Success       = $false
            BackupPath    = $null
            UpdatedFields = @{}
            Errors        = @("User cancelled operation")
            LogPath       = $null
        }
    }

    $field = $menuResult.Field
    $newValue = $menuResult.Value

    # Phase 3: Backup, Update, Write, Verify
    try {
        Write-Host ""
        Write-Host "Processing change..." -ForegroundColor Cyan

        # Create backup
        $backup = Backup-ConfigFile -ConfigPath $prereq.ConfigPath
        Write-Host "Backup created: $(Split-Path $backup -Leaf)"

        # Update JSON
        $newJson = Update-ConfigJson -ConfigPath $prereq.ConfigPath -Field $field -Value $newValue
        Write-Host "Configuration updated in memory"

        # Atomic write
        $written = Write-ConfigFile -ConfigPath $prereq.ConfigPath -JsonContent $newJson
        Write-Host "Changes written to disk"

        # Verify
        $verify = Verify-ConfigChange -ConfigPath $prereq.ConfigPath -Field $field -ExpectedValue $newValue

        if (-not $verify.Verified) {
            # Rollback on verification failure
            Copy-Item $backup $prereq.ConfigPath -Force
            $errors.Add("Verification failed: $($verify.Message). Rolled back to backup.") | Out-Null
            Write-Host "ERROR: $($verify.Message)" -ForegroundColor Red
            Write-Host "Rolled back to backup" -ForegroundColor Green

            return @{
                Success       = $false
                BackupPath    = $backup
                UpdatedFields = @{}
                Errors        = $errors
                LogPath       = $null
            }
        }

        Write-Host "Verification passed"

        $updatedFields[$field] = $newValue

        Write-Host ""
        Write-Host "SUCCESS: Configuration updated!" -ForegroundColor Green
        Write-Host "Field: $field"
        Write-Host "Backup: $(Split-Path $backup -Leaf)"

        if ($prereq.BotRunning) {
            Write-Host ""
            Write-Host "Restart the bot for changes to take effect." -ForegroundColor Yellow
        }

        return @{
            Success       = $true
            BackupPath    = $backup
            UpdatedFields = $updatedFields
            Errors        = @()
            LogPath       = $null
        }
    }
    catch {
        $errors.Add("Error during save: $_") | Out-Null
        Write-Host "ERROR: $_" -ForegroundColor Red

        if ($null -ne $backup -and (Test-Path $backup)) {
            Copy-Item $backup $prereq.ConfigPath -Force -ErrorAction SilentlyContinue
            Write-Host "Rolled back to backup" -ForegroundColor Green
        }

        return @{
            Success       = $false
            BackupPath    = $backup
            UpdatedFields = @{}
            Errors        = $errors
            LogPath       = $null
        }
    }
}
