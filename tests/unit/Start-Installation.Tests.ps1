BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force

    # These tests must never touch the real installation. The previous version
    # called Start-Installation against $env:LOCALAPPDATA\BATCRelayBot with no
    # isolation, which ran pip for real and overwrote the developer's own
    # config.json on every test run.
    $script:SandboxRoot = Join-Path ([System.IO.Path]::GetTempPath()) "batc-install-tests"

    function New-Sandbox {
        $path = Join-Path $script:SandboxRoot ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        return $path
    }

    function New-TestPrerequisites {
        param([string]$PythonPath)
        return @{
            Python      = @{ Found = $true; Path = $PythonPath; Version = "Python 3.12.0" }
            FFmpeg      = @{ Found = $true; Path = "C:\ffmpeg\bin\ffmpeg.exe"; Version = "n7.1" }
            VoiceMeeter = @{
                Found = $true
                Path = "C:\Program Files (x86)\VB\Voicemeeter"
                ExePath = "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter_x64.exe"
                ProcessName = "voicemeeter_x64"
            }
            BeyondATC   = @{ Found = $false; Path = $null; ExePath = $null; ProcessName = $null }
        }
    }

    function New-TestDiscordConfig {
        return @{
            BotToken        = "test-token-value"
            GuildId         = "123456789012345678"
            AudioDeviceName = "VoiceMeeter Output (VB-Audio Voicemeeter VAIO)"
        }
    }
}

AfterAll {
    if ($script:SandboxRoot -and (Test-Path $script:SandboxRoot)) {
        Remove-Item $script:SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Start-Installation" {

    Context "with a working environment" {
        BeforeAll {
            # A stub interpreter: pip must not actually run during unit tests,
            # and the real Python may not be present on a CI runner.
            $script:StubDir = New-Sandbox
            $script:StubPython = Join-Path $script:StubDir "python.cmd"
            Set-Content -Path $script:StubPython -Value "@echo off`r`nexit /b 0" -Encoding ASCII

            $script:Install = New-Sandbox
            $script:Result = Start-Installation `
                -Prerequisites (New-TestPrerequisites -PythonPath $script:StubPython) `
                -DiscordConfig (New-TestDiscordConfig) `
                -InstallPath $script:Install
        }

        It "reports success" {
            $script:Result.Success | Should -BeTrue -Because $script:Result.Error
        }

        It "returns InstallPath, ConfigPath and LogPath" {
            $script:Result.Keys | Should -Contain "InstallPath"
            $script:Result.Keys | Should -Contain "ConfigPath"
            $script:Result.Keys | Should -Contain "LogPath"
        }

        It "installs into the requested directory, not the default one" {
            $script:Result.InstallPath | Should -Be $script:Install
        }

        It "copies bot.py next to the config" {
            Test-Path (Join-Path $script:Install "bot.py") | Should -BeTrue
        }

        It "writes the config in the schema bot.py reads" {
            $config = Get-Content $script:Result.ConfigPath -Raw | ConvertFrom-Json
            $config.bot_token         | Should -Be "test-token-value"
            $config.guild_id          | Should -Be 123456789012345678
            $config.audio_device_name | Should -Be "VoiceMeeter Output (VB-Audio Voicemeeter VAIO)"

            # No channel: it is decided per !BATCjoin.
            $config.PSObject.Properties.Name | Should -Not -Contain 'voice_channel_id'
        }

        It "writes a log" {
            Test-Path $script:Result.LogPath | Should -BeTrue
        }
    }

    Context "when the environment is broken" {
        It "returns a reason instead of throwing when pip fails" {
            $stubDir = New-Sandbox
            $failingPython = Join-Path $stubDir "python.cmd"
            Set-Content -Path $failingPython -Value "@echo off`r`nexit /b 1" -Encoding ASCII

            $result = Start-Installation `
                -Prerequisites (New-TestPrerequisites -PythonPath $failingPython) `
                -DiscordConfig (New-TestDiscordConfig) `
                -InstallPath (New-Sandbox)

            $result.Success | Should -BeFalse
            $result.Error   | Should -Match 'dependencies'
        }
    }
}

Describe "Test-InstallationResult" {

    BeforeAll {
        $script:VerifyDir = New-Sandbox
        Copy-Item "$PSScriptRoot\..\..\bot.py" -Destination $script:VerifyDir -Force
        $script:VerifyConfig = Join-Path $script:VerifyDir "config.json"
    }

    It "accepts a config that satisfies every key bot.py requires" {
        @{
            bot_token         = "t"
            guild_id          = 123456789012345678
            audio_device_name = "VoiceMeeter Output"
        } | ConvertTo-Json | Set-Content $script:VerifyConfig -Encoding UTF8

        (Test-InstallationResult -InstallPath $script:VerifyDir -ConfigPath $script:VerifyConfig).Valid |
            Should -BeTrue
    }

    It "rejects the pre-1.4.0 schema" {
        @{
            bot_token  = "t"
            server_id  = "123456789012345678"
            channel_id = "987654321098765432"
        } | ConvertTo-Json | Set-Content $script:VerifyConfig -Encoding UTF8

        $result = Test-InstallationResult -InstallPath $script:VerifyDir -ConfigPath $script:VerifyConfig
        $result.Valid | Should -BeFalse
        ($result.Problems -join ' ') | Should -Match 'guild_id'
    }

    It "rejects an empty audio_device_name, which bot.py treats as missing" {
        @{
            bot_token         = "t"
            guild_id          = 123456789012345678
            audio_device_name = ""
        } | ConvertTo-Json | Set-Content $script:VerifyConfig -Encoding UTF8

        $result = Test-InstallationResult -InstallPath $script:VerifyDir -ConfigPath $script:VerifyConfig
        $result.Valid | Should -BeFalse
        ($result.Problems -join ' ') | Should -Match 'audio_device_name'
    }

    It "reports malformed JSON rather than throwing" {
        Set-Content $script:VerifyConfig -Value "{ this is not json" -Encoding UTF8
        $result = Test-InstallationResult -InstallPath $script:VerifyDir -ConfigPath $script:VerifyConfig
        $result.Valid | Should -BeFalse
    }
}

Describe "Installer helper resolution" {

    It "Start-Installation is exported" {
        { Get-Command Start-Installation -ErrorAction Stop } | Should -Not -Throw
    }

    It "finds requirements.txt from the repository layout" {
        $previous = Get-Location
        try {
            Set-Location "$PSScriptRoot\..\.."
            Get-RequirementsPath | Should -Not -BeNullOrEmpty
        } finally {
            Set-Location $previous
        }
    }

    It "finds the directory containing bot.py" {
        $previous = Get-Location
        try {
            Set-Location "$PSScriptRoot\..\.."
            $path = Get-BotFilesPath
            $path | Should -Not -BeNullOrEmpty
            Test-Path (Join-Path $path "bot.py") | Should -BeTrue
        } finally {
            Set-Location $previous
        }
    }
}
