@{
    RootModule            = 'BATCRelayBot.psm1'
    ModuleVersion         = '1.6.3'
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
            ReleaseNotes = 'The bot runs under a watcher that records how it ended - exit code, time, duration - in install.log, and restarts it ten seconds after any exit that was not asked for, back into the channel it was in, up to three times an hour. A heartbeat every five minutes tells a quiet bot from a dead one. A voice connection lost to a network blip is rebuilt by the bot itself; before, it could sit silent in the channel for as long as it ran. This release changes bot.py: run Update-Module, then Install-BATCRelayBot in a new window and press Enter. See CHANGELOG.md.'
        }
    }
}
