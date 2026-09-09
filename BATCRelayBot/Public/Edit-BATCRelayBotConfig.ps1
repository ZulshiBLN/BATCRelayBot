#Requires -Version 5.1

function Edit-BATCRelayBotConfig {
    <#
    .SYNOPSIS
    Changes settings in an existing installation without reinstalling.

    .DESCRIPTION
    Edits the fields bot.py actually reads: the bot token, the server ID, the
    voice channel ID and the audio device. Each change is backed up, written
    atomically, read back and verified; a failed verification rolls that file
    back to its backup.

    The editor stays open. It used to exit after a single change, so correcting
    two fields meant running it twice and reading the same warnings again.

    Disabled since v1.3.10 for good reason - the editor wrote `token` while the
    installer wrote `bot_token`, so an edited token went into a field nothing
    read and the bot kept using the old one. That mapping now has a single
    definition in Get-ConfigFieldMap, and it is covered by tests.

    .PARAMETER InstallPath
    Installation directory. Defaults to $env:LOCALAPPDATA\BATCRelayBot.

    .PARAMETER PassThru
    Returns the result object. Without it nothing is written to the pipeline,
    so quitting the menu no longer prints "Cancelled by the user" as a table.

    .EXAMPLE
    Edit-BATCRelayBotConfig

    .EXAMPLE
    $result = Edit-BATCRelayBotConfig -PassThru
    if ($result.Success) { "Changed: $($result.UpdatedFields.Keys)" }

    .OUTPUTS
    With -PassThru, a hashtable with Success, BackupPath, UpdatedFields,
    Errors. UpdatedFields holds every field changed in the session, and
    BackupPath the backup taken before the last of them.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$InstallPath = (Join-Path $env:LOCALAPPDATA "BATCRelayBot"),
        [switch]$PassThru
    )

    # Initialised up front. Both of these used to be referenced without ever
    # being created - $errors.Add on the rollback path and $updatedFields[...]
    # on the success path - so the function threw on whichever branch it took.
    $errors = [System.Collections.ArrayList]@()
    $updatedFields = @{}
    $backup = $null

    # ---- Phase 1: can we edit at all? -----------------------------------
    $prereq = Confirm-ConfigEditorPrerequisites -InstallPath $InstallPath

    if (-not $prereq.Valid) {
        Write-Host ""
        foreach ($problem in $prereq.Errors) {
            Write-Host "  $problem" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "  Run Install-BATCRelayBot first." -ForegroundColor Yellow
        Write-Host ""
        return (Out-CommandResult -PassThru:$PassThru -Result @{
            Success = $false; BackupPath = $null; UpdatedFields = @{}
            Errors = @($prereq.Errors)
        })
    }

    # ---- Phase 2: change fields until the user quits ---------------------
    while ($true) {
        $menuResult = Show-ConfigEditorMenu -ConfigPath $prereq.ConfigPath
        if ($null -eq $menuResult) { break }

        $field = $menuResult.Field
        $newValue = $menuResult.Value

        # Back up, write, verify, roll back on failure.
        try {
            Write-Host ""
            Write-Host "  Applying change..." -ForegroundColor Cyan

            $backup = Backup-ConfigFile -ConfigPath $prereq.ConfigPath
            Write-Host "    Backup: $(Split-Path $backup -Leaf)" -ForegroundColor Gray

            $newJson = Update-ConfigJson -ConfigPath $prereq.ConfigPath -Field $field -Value $newValue
            Write-ConfigFile -ConfigPath $prereq.ConfigPath -JsonContent $newJson | Out-Null

            # The write drops the file's restriction along with the old file, so
            # reapply it before anything else can read the token.
            Protect-BotConfigFile -ConfigPath $prereq.ConfigPath | Out-Null

            $verify = Verify-ConfigChange -ConfigPath $prereq.ConfigPath -Field $field -ExpectedValue $newValue

            if (-not $verify.Verified) {
                Copy-Item $backup $prereq.ConfigPath -Force
                Protect-BotConfigFile -ConfigPath $prereq.ConfigPath | Out-Null

                $errors.Add("$($verify.Message). Rolled back to the backup.") | Out-Null
                Write-Host "    FAILED: $($verify.Message)" -ForegroundColor Red
                Write-Host "    Rolled back - config.json is unchanged." -ForegroundColor Yellow

                # Back to the menu: the change did not happen, and the file is
                # as it was, so there is nothing to stop the user retrying.
                continue
            }

            $definition = Get-ConfigFieldDefinition -Field $field
            $updatedFields[$field] = $newValue

            Write-Host "    Verified." -ForegroundColor Green
            Write-Host "  $($definition.Label) updated." -ForegroundColor Green
        }
        catch {
            # Sanitised: an exception raised while handling the token can carry it.
            $message = Remove-SensitiveData -Text $_.Exception.Message
            $errors.Add("Error while saving: $message") | Out-Null
            Write-Host "    ERROR: $message" -ForegroundColor Red

            if ($backup -and (Test-Path $backup)) {
                Copy-Item $backup $prereq.ConfigPath -Force -ErrorAction SilentlyContinue
                Protect-BotConfigFile -ConfigPath $prereq.ConfigPath | Out-Null
                Write-Host "    Rolled back - config.json is unchanged." -ForegroundColor Yellow
            }

            # An unexpected exception is a reason to stop, not to offer the
            # menu again over a state nobody has established.
            break
        }
    }

    Write-Host ""

    # Said once, on the way out. It used to be printed on entry when the bot
    # was running and again after every change, and the menu claimed "No
    # changes made" on quitting even when several had been.
    if ($updatedFields.Count -gt 0 -and $prereq.BotRunning) {
        Write-Host "  Restart the bot to apply this: Stop-BATCRelayBot; Start-BATCRelayBot" -ForegroundColor Yellow
        Write-Host ""
    }

    if ($updatedFields.Count -eq 0 -and $errors.Count -eq 0) {
        Write-Host "  No changes made." -ForegroundColor Yellow
        Write-Host ""
        return (Out-CommandResult -PassThru:$PassThru -Result @{
            Success = $false; BackupPath = $null; UpdatedFields = @{}
            Errors = @("Cancelled by the user")
        })
    }

    return (Out-CommandResult -PassThru:$PassThru -Result @{
        Success       = ($errors.Count -eq 0)
        BackupPath    = $backup
        UpdatedFields = $updatedFields
        Errors        = @($errors)
    })
}

Export-ModuleMember -Function Edit-BATCRelayBotConfig
