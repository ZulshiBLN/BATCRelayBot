@{
    RootModule            = 'BATCRelayBot.psm1'
    ModuleVersion         = '1.4.0'
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
            ReleaseNotes = 'Repairs the config.json contract between installer and bot: installations before 1.4.0 produced a configuration the bot could not load. Also re-enables Edit-BATCRelayBotConfig, prefixes the Discord commands with BATC, and fixes prerequisite detection and the uninstaller. See CHANGELOG.md.'
        }
    }
}
