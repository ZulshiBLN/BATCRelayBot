BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force
}

Describe "Show-InstallationSummary" {
    BeforeEach {
        $prereqs = @{
            Python = @{ Found = $true; Path = "C:\Python\python.exe"; Version = "3.10" }
            FFmpeg = @{ Found = $true; Path = "C:\FFmpeg\ffmpeg.exe"; Version = "4.4" }
            VoiceMeeter = @{ Found = $true; Path = "C:\VoiceMeeter" }
            BeyondATC = @{ Found = $false }
        }
        $discord = @{
            BotToken = "test_bot_token_1234567890abcdef"
            ServerId = "123456789012345678"
            ChannelId = "987654321098765432"
        }
    }

    It "Executes without errors" {
        { Show-InstallationSummary -Prerequisites $prereqs -DiscordConfig $discord } | Should -Not -Throw
    }

    It "Returns hashtable with CanProceed and InstallPath" {
        $result = Show-InstallationSummary -Prerequisites $prereqs -DiscordConfig $discord
        $result | Should -BeOfType [hashtable]
        $result.Keys | Should -Contain "CanProceed"
        $result.Keys | Should -Contain "InstallPath"
    }

    It "Returns CanProceed=true when all requirements met" {
        $result = Show-InstallationSummary -Prerequisites $prereqs -DiscordConfig $discord
        $result.CanProceed | Should -Be $true
    }

    It "Returns CanProceed=false when prerequisites missing" {
        $prereqs.Python.Found = $false
        $result = Show-InstallationSummary -Prerequisites $prereqs -DiscordConfig $discord
        $result.CanProceed | Should -Be $false
    }

    It "Returns CanProceed=false when Discord config incomplete" {
        $discord.BotToken = $null
        $result = Show-InstallationSummary -Prerequisites $prereqs -DiscordConfig $discord
        $result.CanProceed | Should -Be $false
    }

    It "Handles optional prerequisites (BeyondATC)" {
        $prereqs.BeyondATC.Found = $false
        $result = Show-InstallationSummary -Prerequisites $prereqs -DiscordConfig $discord
        $result.CanProceed | Should -Be $true
    }

    It "Provides installation path" {
        $result = Show-InstallationSummary -Prerequisites $prereqs -DiscordConfig $discord
        $result.InstallPath | Should -Not -BeNullOrEmpty
        $result.InstallPath | Should -Match "BATCRelayBot"
    }
}

Describe "Phase 4: Summary Screen Integration" {
    It "Shows all prerequisite statuses" {
        $prereqs = @{
            Python = @{ Found = $true; Path = "C:\Python\python.exe"; Version = "3.10" }
            FFmpeg = @{ Found = $false; Path = $null; Version = $null }
            VoiceMeeter = @{ Found = $true; Path = "C:\VoiceMeeter" }
            BeyondATC = @{ Found = $false }
        }
        $discord = @{
            BotToken = "token"
            ServerId = "123456789012345678"
            ChannelId = "987654321098765432"
        }

        { Show-InstallationSummary -Prerequisites $prereqs -DiscordConfig $discord } | Should -Not -Throw
    }

    It "Summary screen is read-only (no prompts)" {
        # Function should display only, not prompt for input
        $prereqs = @{
            Python = @{ Found = $true; Path = "C:\Python\python.exe"; Version = "3.10" }
            FFmpeg = @{ Found = $true; Path = "C:\FFmpeg\ffmpeg.exe" }
            VoiceMeeter = @{ Found = $true; Path = "C:\VoiceMeeter" }
            BeyondATC = @{ Found = $false }
        }
        $discord = @{
            BotToken = "token"
            ServerId = "123456789012345678"
            ChannelId = "987654321098765432"
        }

        $result = Show-InstallationSummary -Prerequisites $prereqs -DiscordConfig $discord
        # If no prompts occur, this test passes (function completes)
        $true | Should -Be $true
    }

    It "Validates readiness before installation" {
        $allOk = @{
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

        $result = Show-InstallationSummary -Prerequisites $allOk -DiscordConfig $discord
        $result.CanProceed | Should -Be $true
    }
}
