# Setup keeps the configuration it finds (1.6.2).
#
# Every release that changes bot.py needs Install-BATCRelayBot run again, and
# until 1.6.2 setup asked for the token, the server ID and the audio device
# from scratch although it had just migrated them. Now: one question when the
# file is complete, only the missing values when it is not, and a kept value
# checked exactly like a typed one.

BeforeAll {
    Import-Module "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1" -Force

    $script:Devices = @(
        'Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)',
        'Voicemeeter Out B2 (VB-Audio Voicemeeter VAIO)'
    )

    function New-ConfigFile {
        param([hashtable]$Fields)
        $path = Join-Path $env:TEMP ("resolve-" + [guid]::NewGuid().ToString('N') + ".json")
        $Fields | ConvertTo-Json | Set-Content $path -Encoding UTF8
        $path
    }

    function New-CompleteConfig {
        New-ConfigFile @{
            bot_token         = 'a' * 60
            guild_id          = 123456789012345678
            audio_device_name = 'Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)'
        }
    }
}

Describe "Resolve-BotConfiguration with a complete configuration" {

    BeforeEach {
        Mock -ModuleName BATCRelayBot Write-InstallLog { }
        Mock -ModuleName BATCRelayBot Get-DshowAudioDevice { $script:Devices }
        Mock -ModuleName BATCRelayBot Test-DiscordBotToken { @{ Valid = $true; BotName = 'BATC Relay' } }
        Mock -ModuleName BATCRelayBot Read-DiscordToken { 'typed-token-' + ('b' * 50) }
        Mock -ModuleName BATCRelayBot Read-DiscordSnowflake { '999999999999999999' }
        Mock -ModuleName BATCRelayBot Select-AudioDevice { 'Voicemeeter Out B2 (VB-Audio Voicemeeter VAIO)' }
    }

    It "asks once, and Enter keeps all three values" {
        $path = New-CompleteConfig
        Mock -ModuleName BATCRelayBot Read-Host { '' }

        $result = Resolve-BotConfiguration -ConfigPath $path -FFmpegPath 'ffmpeg.exe' 6>$null

        $result.BotToken | Should -Be ('a' * 60)
        $result.GuildId | Should -Be '123456789012345678'
        $result.AudioDeviceName | Should -Be 'Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)'
        Should -Invoke -ModuleName BATCRelayBot Read-Host -Times 1 -Exactly
        Should -Invoke -ModuleName BATCRelayBot Read-DiscordToken -Times 0
        Should -Invoke -ModuleName BATCRelayBot Read-DiscordSnowflake -Times 0
        Should -Invoke -ModuleName BATCRelayBot Select-AudioDevice -Times 0
    }

    It "checks the kept token against the API like a typed one" {
        $path = New-CompleteConfig
        Mock -ModuleName BATCRelayBot Read-Host { 'y' }

        Resolve-BotConfiguration -ConfigPath $path -FFmpegPath 'ffmpeg.exe' 6>$null | Out-Null

        Should -Invoke -ModuleName BATCRelayBot Test-DiscordBotToken -Times 1 -Exactly `
            -ParameterFilter { $Token -eq ('a' * 60) }
    }

    It "answers n with the three questions of a clean run" {
        $path = New-CompleteConfig
        Mock -ModuleName BATCRelayBot Read-Host { 'n' }

        $result = Resolve-BotConfiguration -ConfigPath $path -FFmpegPath 'ffmpeg.exe' 6>$null

        Should -Invoke -ModuleName BATCRelayBot Read-DiscordToken -Times 1 -Exactly
        Should -Invoke -ModuleName BATCRelayBot Read-DiscordSnowflake -Times 1 -Exactly
        Should -Invoke -ModuleName BATCRelayBot Select-AudioDevice -Times 1 -Exactly
        $result.GuildId | Should -Be '999999999999999999'
    }

    It "asks only for a kept token the API rejects, and keeps the rest" {
        $path = New-CompleteConfig
        Mock -ModuleName BATCRelayBot Read-Host { '' }
        Mock -ModuleName BATCRelayBot Test-DiscordBotToken { @{ Valid = $false; Error = '401 Unauthorized' } }

        $result = Resolve-BotConfiguration -ConfigPath $path -FFmpegPath 'ffmpeg.exe' 6>$null

        Should -Invoke -ModuleName BATCRelayBot Read-DiscordToken -Times 1 -Exactly
        Should -Invoke -ModuleName BATCRelayBot Read-DiscordSnowflake -Times 0
        Should -Invoke -ModuleName BATCRelayBot Select-AudioDevice -Times 0
        $result.BotToken | Should -Match '^typed-token-'
        $result.GuildId | Should -Be '123456789012345678'
    }

    It "asks only for a kept device that ffmpeg no longer lists" {
        $path = New-ConfigFile @{
            bot_token         = 'a' * 60
            guild_id          = 123456789012345678
            audio_device_name = 'Voicemeeter Out B3 (VB-Audio Voicemeeter VAIO)'
        }
        Mock -ModuleName BATCRelayBot Read-Host { '' }

        $result = Resolve-BotConfiguration -ConfigPath $path -FFmpegPath 'ffmpeg.exe' 6>$null

        Should -Invoke -ModuleName BATCRelayBot Select-AudioDevice -Times 1 -Exactly
        Should -Invoke -ModuleName BATCRelayBot Read-DiscordToken -Times 0
        $result.AudioDeviceName | Should -Be 'Voicemeeter Out B2 (VB-Audio Voicemeeter VAIO)'
    }

    It "shows the server ID masked, never in full" {
        $path = New-CompleteConfig
        Mock -ModuleName BATCRelayBot Read-Host { '' }

        # Only what Write-Host put on the screen - the returned hashtable
        # carries the full ID on purpose, for config.json.
        $screen = Resolve-BotConfiguration -ConfigPath $path -FFmpegPath 'ffmpeg.exe' 6>&1 |
            Where-Object { $_ -is [System.Management.Automation.InformationRecord] } |
            Out-String

        $screen | Should -Not -Match '123456789012345678'
        $screen | Should -Match '\.\.\.5678'
        $screen | Should -Not -Match ('a' * 60)
    }
}

Describe "Resolve-BotConfiguration with less than a complete configuration" {

    BeforeEach {
        Mock -ModuleName BATCRelayBot Write-InstallLog { }
        Mock -ModuleName BATCRelayBot Get-DshowAudioDevice { $script:Devices }
        Mock -ModuleName BATCRelayBot Test-DiscordBotToken { @{ Valid = $true; BotName = 'BATC Relay' } }
        Mock -ModuleName BATCRelayBot Read-DiscordToken { 'typed-token-' + ('b' * 50) }
        Mock -ModuleName BATCRelayBot Read-DiscordSnowflake { '999999999999999999' }
        Mock -ModuleName BATCRelayBot Select-AudioDevice { 'Voicemeeter Out B2 (VB-Audio Voicemeeter VAIO)' }
        Mock -ModuleName BATCRelayBot Read-Host { throw "the keep question must not be asked here" }
    }

    It "asks only for what is missing, without the keep question" {
        $path = New-ConfigFile @{
            bot_token = 'a' * 60
            guild_id  = 123456789012345678
        }

        $result = Resolve-BotConfiguration -ConfigPath $path -FFmpegPath 'ffmpeg.exe' 6>$null

        Should -Invoke -ModuleName BATCRelayBot Select-AudioDevice -Times 1 -Exactly
        Should -Invoke -ModuleName BATCRelayBot Read-DiscordToken -Times 0
        Should -Invoke -ModuleName BATCRelayBot Read-DiscordSnowflake -Times 0
        $result.BotToken | Should -Be ('a' * 60)
        $result.AudioDeviceName | Should -Be 'Voicemeeter Out B2 (VB-Audio Voicemeeter VAIO)'
    }

    It "asks all three on a clean machine, exactly as before" {
        $result = Resolve-BotConfiguration -ConfigPath (Join-Path $env:TEMP 'does-not-exist.json') `
            -FFmpegPath 'ffmpeg.exe' 6>$null

        Should -Invoke -ModuleName BATCRelayBot Read-DiscordToken -Times 1 -Exactly
        Should -Invoke -ModuleName BATCRelayBot Read-DiscordSnowflake -Times 1 -Exactly
        Should -Invoke -ModuleName BATCRelayBot Select-AudioDevice -Times 1 -Exactly
        $result.BotToken | Should -Match '^typed-token-'
    }

    It "returns nothing when a prompt is abandoned" {
        Mock -ModuleName BATCRelayBot Read-DiscordToken { $null }

        $result = Resolve-BotConfiguration -ConfigPath (Join-Path $env:TEMP 'does-not-exist.json') `
            -FFmpegPath 'ffmpeg.exe' 6>$null

        $result | Should -BeNullOrEmpty
    }

    It "skips the device entirely with -SkipAudioDevice" {
        $result = Resolve-BotConfiguration -ConfigPath (Join-Path $env:TEMP 'does-not-exist.json') `
            -FFmpegPath 'ffmpeg.exe' -SkipAudioDevice 6>$null

        Should -Invoke -ModuleName BATCRelayBot Select-AudioDevice -Times 0
        $result.AudioDeviceName | Should -Be ''
    }
}

Describe "Format-Snowflake" {

    It "shows the last four digits behind an ellipsis" {
        Format-Snowflake '123456789012345678' | Should -Be '...5678'
    }

    It "names an empty value rather than masking nothing" {
        Format-Snowflake $null | Should -Be '(not set)'
        Format-Snowflake '' | Should -Be '(not set)'
    }

    It "does not pretend a short value is an ID" {
        Format-Snowflake '42' | Should -Be '...42'
    }
}
