@{
    RootModule            = 'BATCRelayBot.psm1'
    ModuleVersion         = '1.0.0'
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
        'Get-BATCRelayBotStatus'
    )

    CmdletsToExport       = @()
    VariablesToExport     = @()
    AliasesToExport       = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('Discord', 'Bot', 'Audio', 'VoiceMeeter', 'BATC')
            LicenseUri = 'https://github.com/BroscheMichel/ATC-Relay-Bot/blob/main/LICENSE'
            ProjectUri = 'https://github.com/BroscheMichel/ATC-Relay-Bot'
            ReleaseNotes = 'Initial release'
        }
    }
}
