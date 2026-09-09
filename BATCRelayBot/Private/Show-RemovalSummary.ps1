#Requires -Version 5.1

function Show-RemovalSummary {
    <#
    .SYNOPSIS
    Lists what the removal will delete (uninstaller phase 2). Read-only.

    .DESCRIPTION
    This used to open its own banner - "BATCRelayBot Removal - What Will Be
    Deleted?" - directly under the caller's "[2/5] What will be removed", print
    the installation path twice more after phase 1 had already reported it, list
    every log file a second time under a separate "Logs & Artifacts" heading,
    and finish with a disk-space figure that read "Approximately: 0.01 MB".

    The manual steps it ended with have moved to the summary shown after the
    removal, where they are still true and where the user is when they matter.

    .PARAMETER BotPath
    Installation directory whose contents are about to be deleted.
    #>
    [OutputType([void])]
    param(
        [string]$BotPath = (Join-Path $env:LOCALAPPDATA "BATCRelayBot")
    )

    $files = @()
    if (Test-Path $BotPath) {
        $files = @(Get-ChildItem -Path $BotPath -Recurse -File -ErrorAction SilentlyContinue |
                   Select-Object -ExpandProperty Name | Sort-Object)
    }

    if ($files.Count -eq 0) {
        Write-Host "        Nothing found to delete." -ForegroundColor Gray
        Write-Host ""
        return
    }

    Write-Host "        $($files.Count) file$(if ($files.Count -ne 1) { 's' }):" -ForegroundColor Gray
    foreach ($name in $files) {
        Write-Host "          $name" -ForegroundColor DarkGray
    }
    Write-Host ""

    if (Test-Path (Join-Path $BotPath "config.json")) {
        Write-Host "        config.json holds your bot token. It is overwritten three times" -ForegroundColor Yellow
        Write-Host "        before deletion, which an SSD may still not honour - so reset the" -ForegroundColor Yellow
        Write-Host "        token afterwards at https://discord.com/developers/applications" -ForegroundColor Yellow
        Write-Host ""
    }
}

Export-ModuleMember -Function Show-RemovalSummary
