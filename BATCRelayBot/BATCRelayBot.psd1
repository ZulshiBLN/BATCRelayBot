@{
    RootModule            = 'BATCRelayBot.psm1'
    ModuleVersion         = '1.5.0'
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
            ReleaseNotes = 'The bot now joins the voice channel you are in when you say !BATCjoin, or one you name with !BATCjoin <name or id>, so voice_channel_id is gone from the configuration - existing installations keep the field and it is ignored. A missing permission is explained by direct message instead of a generic refusal. The commands no longer print their result object; pass -PassThru for it. Fixes: stopping the bot could leave the machine without audio, two bots could run at once, and an uninstall that could not delete a file reported itself as tidy. See CHANGELOG.md.'
        }
    }
}
