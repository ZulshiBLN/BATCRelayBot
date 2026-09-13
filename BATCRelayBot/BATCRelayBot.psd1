@{
    RootModule            = 'BATCRelayBot.psm1'
    ModuleVersion         = '1.6.2'
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
            ReleaseNotes = 'Setup keeps the configuration it finds: on an upgrade it shows the token (redacted), server ID and audio device and asks once whether to keep them - Enter keeps all three, so an upgrade is one keystroke. A kept token is checked against Discord and a kept device against ffmpeg like typed ones. Setup stops when a newer version is installed than the one running and asks for a new window. The server ID is shown masked. See CHANGELOG.md.'
        }
    }
}
