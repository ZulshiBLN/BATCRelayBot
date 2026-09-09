#Requires -Version 5.1

function Show-PostRemovalSummary {
    <#
    .SYNOPSIS
    Reports what the removal actually did (uninstaller, after phase 5).

    .DESCRIPTION
    This was four banner-separated sections over a hundred lines. Worse than the
    length: it told users to remove VoiceMeeter through Control Panel, which
    leaves its audio drivers behind - VB-Audio's own installer is the only thing
    that removes it properly - and it never mentioned BeyondATC, which is not
    removed either.

    Anything still on disk is named. A removal that failed on a locked file used
    to be followed by "Nothing to clean up", and then by a summary that said
    Success: False in a block the user could not read.
    #>
    [OutputType([void])]
    param(
        [hashtable]$RemovalResult = @{}
    )

    $leftovers = @($RemovalResult.Leftovers)
    $errors    = @($RemovalResult.Errors)

    Write-Host ""
    if ($RemovalResult.Success) {
        Write-Host "  BATCRelayBot has been removed." -ForegroundColor Green
    } else {
        Write-Host "  BATCRelayBot was only partly removed." -ForegroundColor Yellow
    }
    Write-Host ""

    # A path that could not be removed appears once, with its reason attached.
    # Listing it under "what went wrong" and again under "still on disk" said
    # the same thing twice in different words.
    if ($leftovers.Count -gt 0) {
        Write-Host "  Still on disk - delete these by hand:" -ForegroundColor Yellow
        foreach ($item in $leftovers) {
            Write-Host "    $item" -ForegroundColor Yellow

            $reason = $errors | Where-Object { "$_".Contains($item) } | Select-Object -First 1
            if ($reason) {
                Write-Host "      $($reason -replace '^Could not remove .*?: ', '')" -ForegroundColor DarkYellow
            }
        }
        Write-Host ""
    }

    # Whatever is left: a dependency that would not uninstall, a bot that would
    # not stop. These have no path of their own to hang from.
    $unexplained = @($errors | Where-Object {
        $problem = "$_"
        -not ($leftovers | Where-Object { $problem.Contains($_) })
    })

    if ($unexplained.Count -gt 0) {
        Write-Host "  What went wrong:" -ForegroundColor Yellow
        foreach ($problem in $unexplained) {
            Write-Host "    $problem" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    if (@($RemovalResult.RemovedDependencies).Count -gt 0) {
        Write-Host "  Also removed:" -ForegroundColor Cyan
        foreach ($dependency in $RemovalResult.RemovedDependencies) {
            Write-Host "    $dependency" -ForegroundColor Gray
        }
        Write-Host ""
    }

    # The token outlives the file. Overwriting is not erasure on an SSD, so this
    # stays even when everything else was cut.
    Write-Host "  Reset your bot token" -ForegroundColor Yellow
    Write-Host "    config.json was overwritten and deleted, which an SSD may not honour." -ForegroundColor Gray
    Write-Host "    https://discord.com/developers/applications > your app > Bot > Reset Token" -ForegroundColor Gray
    Write-Host ""

    Write-Host "  Not removed by this uninstaller:" -ForegroundColor Cyan
    Write-Host "    1. VoiceMeeter - use VB-Audio's own installer to uninstall it." -ForegroundColor Gray
    Write-Host "       Settings > Apps leaves its audio drivers behind." -ForegroundColor Gray
    Write-Host "       https://vb-audio.com/Voicemeeter/" -ForegroundColor DarkGray
    Write-Host "    2. BeyondATC - use its own uninstaller." -ForegroundColor Gray
    Write-Host "       https://beyondatc.net/" -ForegroundColor DarkGray
    Write-Host "    3. This PowerShell module - Uninstall-Module BATCRelayBot" -ForegroundColor Gray
    Write-Host ""

    if ($RemovalResult.LogPath) {
        Write-Host "  Removal log kept at $($RemovalResult.LogPath)" -ForegroundColor DarkGray
        Write-Host ""
    }
}

Export-ModuleMember -Function Show-PostRemovalSummary
