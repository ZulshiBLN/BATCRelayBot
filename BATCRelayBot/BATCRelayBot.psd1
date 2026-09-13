@{
    RootModule            = 'BATCRelayBot.psm1'
    ModuleVersion         = '1.6.1'
    GUID                  = '12345678-1234-1234-1234-123456789012'
    Author                = 'Michel Brosche'
    CompanyName           = ''
    Copyright             = '(c) 2026 Michel Brosche. All rights reserved.'
    Description           = 'Discord bot that live-streams audio from a Windows recording device into a Discord voice channel, with automation for VoiceMeeter and BeyondATC.'

    PowerShellVersion     = '5.1'

    FunctionsToExport     = @(
        'Install-BATCRelayBot',
        'Start-BATCRelayBot',
        'Stop-BATCRelayBot',
        'Uninstall-BATCRelayBot',
        'Get-BATCRelayBotStatus',
        'Edit-BATCRelayBotConfig'
    )

    CmdletsToExport       = @()
    VariablesToExport     = @()
    AliasesToExport       = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('Discord', 'Bot', 'Audio', 'VoiceMeeter', 'BATC')
            LicenseUri = 'https://github.com/ZulshiBLN/BATCRelayBot/blob/main/LICENSE'
            ProjectUri = 'https://github.com/ZulshiBLN/BATCRelayBot'
            # Shown on the PSGallery package page. Keep this current with the
            # version above - it still described 1.0.0 at 1.3.16.
            ReleaseNotes = 'ATC text is now one message that grows as the controller speaks, a new one only when 2000 characters are full, and every page is deleted when the bot leaves - !BATCleave, !BATCshutdown, Stop-BATCRelayBot, or the next start after a kill. The replies to !BATC commands stay. No new permission. Fixed: the uninstaller now counts hidden files. See CHANGELOG.md.'
        }
    }
}
