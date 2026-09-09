#Requires -Version 5.1

function Show-PostInstallationMessage {
    <#
    .SYNOPSIS
    Closes a successful installation: what was written, what to run next, where
    to read more.

    .DESCRIPTION
    This used to say the installation had succeeded three times over - a banner,
    a heading and a sentence - then list four troubleshooting recipes that
    belong in the documentation, then two competing "next steps" lists, one of
    which told the user to start the bot with a raw python command the module
    has a command for.

    It also returned a hashtable that nothing consumed, and was called without
    Out-Null, so PowerShell printed those fields to the screen on top of the
    result Install-BATCRelayBot returned. That is why the Name/Value dump after
    an install showed every key twice. It returns nothing now.

    Troubleshooting lives in docs/TROUBLESHOOTING.md, which is linked rather
    than summarised: a copy in the terminal is a copy that goes stale.
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    $repo = "https://github.com/ZulshiBLN/BATCRelayBot"

    Write-Host ""
    Write-Host "  INSTALLATION SUCCESSFUL!" -ForegroundColor Green
    Write-Host ""

    Write-Host "  Installation Details:" -ForegroundColor Cyan
    Write-Host "    Installation Path   $InstallPath" -ForegroundColor Gray
    Write-Host "    Configuration File  $ConfigPath" -ForegroundColor Gray
    Write-Host "    Installation Log    $LogPath" -ForegroundColor Gray
    Write-Host ""

    Write-Host "  What's Next:" -ForegroundColor Cyan
    Write-Host "    Start-BATCRelayBot       starts the bot and connects it to Discord" -ForegroundColor Gray
    Write-Host "    Get-BATCRelayBotStatus   reports whether it is running" -ForegroundColor Gray
    Write-Host "    Stop-BATCRelayBot        stops it and leaves the voice channel" -ForegroundColor Gray
    Write-Host "    Edit-BATCRelayBotConfig  changes the token, server, channel or device" -ForegroundColor Gray
    Write-Host "    Uninstall-BATCRelayBot   removes this installation" -ForegroundColor Gray
    Write-Host ""
    Write-Host "    Start it, then type !batchelp in your Discord server. If the bot" -ForegroundColor Gray
    Write-Host "    answers, it is connected - !batcjoin then brings it into voice." -ForegroundColor Gray
    Write-Host ""

    Write-Host "  Documentation & Support:" -ForegroundColor Cyan
    Write-Host "    Setup and usage   $repo#readme" -ForegroundColor DarkGray
    Write-Host "    Configuration     $repo/blob/main/docs/CONFIGURATION.md" -ForegroundColor DarkGray
    Write-Host "    Troubleshooting   $repo/blob/main/docs/TROUBLESHOOTING.md" -ForegroundColor DarkGray
    Write-Host ""
}

Export-ModuleMember -Function Show-PostInstallationMessage
