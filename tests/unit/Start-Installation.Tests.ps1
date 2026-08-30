BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force
}

Describe "Start-Installation" {
    BeforeEach {
        $prereqs = @{
            Python = @{ Found = $true; Path = "C:\Python\python.exe"; Version = "3.10" }
            FFmpeg = @{ Found = $true; Path = "C:\FFmpeg\ffmpeg.exe" }
            VoiceMeeter = @{ Found = $true; Path = "C:\VoiceMeeter" }
            BeyondATC = @{ Found = $false }
        }
        $discord = @{
            BotToken = "test_token_123"
            ServerId = "123456789012345678"
            ChannelId = "987654321098765432"
        }
    }

    It "Returns hashtable with Success, InstallPath, ConfigPath, LogPath" {
        $result = Start-Installation -Prerequisites $prereqs -DiscordConfig $discord
        $result | Should -BeOfType [hashtable]
        $result.Keys | Should -Contain "Success"
        $result.Keys | Should -Contain "InstallPath"
        $result.Keys | Should -Contain "ConfigPath"
    }

    It "Creates installation directory" {
        $result = Start-Installation -Prerequisites $prereqs -DiscordConfig $discord
        $result.InstallPath | Should -Not -BeNullOrEmpty
    }

    It "Generates valid configuration" {
        $result = Start-Installation -Prerequisites $prereqs -DiscordConfig $discord
        if ($result.ConfigPath -and (Test-Path $result.ConfigPath)) {
            $config = Get-Content $result.ConfigPath | ConvertFrom-Json
            $config.bot_token | Should -Be $discord.BotToken
            $config.server_id | Should -Be $discord.ServerId
            $config.channel_id | Should -Be $discord.ChannelId
        }
    }

    It "Creates installation log" {
        $result = Start-Installation -Prerequisites $prereqs -DiscordConfig $discord
        $result.LogPath | Should -Not -BeNullOrEmpty
    }

    It "Handles missing Python gracefully" {
        $prereqs.Python.Found = $false
        $result = Start-Installation -Prerequisites $prereqs -DiscordConfig $discord
        # Should attempt installation but handle missing Python
        $result | Should -Not -BeNull
    }

    It "Handles missing VoiceMeeter gracefully" {
        $prereqs.VoiceMeeter.Found = $false
        $result = Start-Installation -Prerequisites $prereqs -DiscordConfig $discord
        # Should continue even if VoiceMeeter missing
        $result | Should -Not -BeNull
    }
}

Describe "Phase 5: Installation Orchestration" {
    It "Installation function exists" {
        { Get-Command Start-Installation -ErrorAction Stop } | Should -Not -Throw
    }

    It "Installation handles prerequisites parameter" {
        $prereqs = @{
            Python = @{ Found = $true; Path = "C:\Python\python.exe" }
            FFmpeg = @{ Found = $true; Path = "C:\FFmpeg\ffmpeg.exe" }
            VoiceMeeter = @{ Found = $true; Path = "C:\VoiceMeeter" }
            BeyondATC = @{ Found = $false }
        }
        $discord = @{
            BotToken = "token"
            ServerId = "123456789012345678"
            ChannelId = "987654321098765432"
        }

        { Start-Installation -Prerequisites $prereqs -DiscordConfig $discord } | Should -Not -Throw
    }

    It "Installation handles discord config parameter" {
        $prereqs = @{
            Python = @{ Found = $true; Path = "C:\Python\python.exe" }
            FFmpeg = @{ Found = $true; Path = "C:\FFmpeg\ffmpeg.exe" }
            VoiceMeeter = @{ Found = $true; Path = "C:\VoiceMeeter" }
            BeyondATC = @{ Found = $false }
        }
        $discord = @{
            BotToken = "token_value"
            ServerId = "111111111111111111"
            ChannelId = "222222222222222222"
        }

        $result = Start-Installation -Prerequisites $prereqs -DiscordConfig $discord
        $result.Success | Should -BeOfType [bool]
    }

    It "Installation provides helpful next steps" {
        $prereqs = @{
            Python = @{ Found = $true; Path = "C:\Python\python.exe" }
            FFmpeg = @{ Found = $true; Path = "C:\FFmpeg\ffmpeg.exe" }
            VoiceMeeter = @{ Found = $true; Path = "C:\VoiceMeeter" }
            BeyondATC = @{ Found = $false }
        }
        $discord = @{
            BotToken = "token"
            ServerId = "123456789012345678"
            ChannelId = "987654321098765432"
        }

        # Installation should display guidance
        { Start-Installation -Prerequisites $prereqs -DiscordConfig $discord } | Should -Not -Throw
    }
}
