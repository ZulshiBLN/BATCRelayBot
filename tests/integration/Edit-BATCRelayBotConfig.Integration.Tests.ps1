#Requires -Version 5.1

<#
.SYNOPSIS
End-to-end test: installer writes a config, the editor changes it, the bot
can still load it.

.DESCRIPTION
The previous version of this file is the reason the config editor shipped
broken. It built its own fixtures using the editor's field names - `token`,
`channel_id` - so the editor agreed with the tests and both disagreed with
what the installer actually wrote. Everything passed while a real edit sent
the new token to a field nothing read.

So this file never invents a config. It generates one with the same function
the installer uses, and checks the result against the key list parsed out of
bot.py.
#>

BeforeAll {
    Import-Module "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1" -Force

    $script:RepoRoot = Resolve-Path "$PSScriptRoot\..\.."

    $botPy = Get-Content (Join-Path $script:RepoRoot "bot.py") -Raw
    $script:BotRequiredKeys = @()
    if ($botPy -match 'REQUIRED_KEYS\s*=\s*\[(.*?)\]') {
        $script:BotRequiredKeys = ([regex]::Matches($Matches[1], '"([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value })
    }

    $script:SandboxRoot = Join-Path ([System.IO.Path]::GetTempPath()) "batc-editor-integration"

    function New-InstalledConfig {
        <#
        Produces a config exactly as Install-BATCRelayBot would, by calling
        the same writer. Never hand-rolled.
        #>
        $installPath = Join-Path $script:SandboxRoot ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $installPath -Force | Out-Null
        $configPath = Join-Path $installPath "config.json"

        $prerequisites = @{
            Python      = @{ Found = $true; Path = "C:\Python312\python.exe" }
            FFmpeg      = @{ Found = $true; Path = "C:\ffmpeg\bin\ffmpeg.exe" }
            VoiceMeeter = @{
                Found = $true; Path = "C:\Program Files (x86)\VB\Voicemeeter"
                ExePath = "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter_x64.exe"
                ProcessName = "voicemeeter_x64"
            }
            BeyondATC   = @{ Found = $false; Path = $null; ExePath = $null; ProcessName = $null }
        }

        $discord = @{
            BotToken        = ("A" * 24) + "." + ("B" * 6) + "." + ("C" * 27)
            GuildId         = "123456789012345678"
            AudioDeviceName = "Voicemeeter Out B3 (VB-Audio Voicemeeter VAIO)"
        }

        New-BotConfigFile -ConfigPath $configPath `
            -Prerequisites $prerequisites -DiscordConfig $discord | Out-Null

        return @{ InstallPath = $installPath; ConfigPath = $configPath }
    }

    function Test-BotCanLoad {
        <# Applies bot.py's own acceptance rule to a config file. #>
        param([string]$ConfigPath)

        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        foreach ($key in $script:BotRequiredKeys) {
            if ([string]::IsNullOrWhiteSpace([string]$config.$key)) { return $false }
        }
        return $true
    }
}

AfterAll {
    if ($script:SandboxRoot -and (Test-Path $script:SandboxRoot)) {
        Remove-Item $script:SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Editor against an installer-generated config" {

    It "starts from a config the bot accepts" {
        $env = New-InstalledConfig
        Test-BotCanLoad -ConfigPath $env.ConfigPath | Should -BeTrue
    }

    It "writes an edited token to the field the installer used" {
        # The original defect: the editor wrote `token` while the installer
        # wrote `bot_token`, so the bot kept the old credentials.
        $env = New-InstalledConfig
        $newToken = ("Z" * 24) + "." + ("Y" * 6) + "." + ("X" * 27)

        $json = Update-ConfigJson -ConfigPath $env.ConfigPath -Field 'Token' -Value $newToken
        Write-ConfigFile -ConfigPath $env.ConfigPath -JsonContent $json | Out-Null

        $config = Get-Content $env.ConfigPath -Raw | ConvertFrom-Json
        $config.bot_token | Should -Be $newToken
        $config.PSObject.Properties.Name | Should -Not -Contain 'token'
    }

    It "leaves the config loadable after every kind of edit" {
        foreach ($edit in @(
            @{ Field = 'Token';       Value = ("Q" * 24) + "." + ("R" * 6) + "." + ("S" * 27) },
            @{ Field = 'Guild';       Value = "222222222222222222" },
            @{ Field = 'AudioDevice'; Value = "Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)" }
        )) {
            $env = New-InstalledConfig
            $json = Update-ConfigJson -ConfigPath $env.ConfigPath -Field $edit.Field -Value $edit.Value
            Write-ConfigFile -ConfigPath $env.ConfigPath -JsonContent $json | Out-Null

            Test-BotCanLoad -ConfigPath $env.ConfigPath |
                Should -BeTrue -Because "editing $($edit.Field) must not make the bot unstartable"
        }
    }

    It "keeps the server ID numeric after editing it" {
        $env = New-InstalledConfig
        $json = Update-ConfigJson -ConfigPath $env.ConfigPath -Field 'Guild' -Value "444444444444444444"
        Write-ConfigFile -ConfigPath $env.ConfigPath -JsonContent $json | Out-Null

        $raw = Get-Content $env.ConfigPath -Raw
        $raw | Should -Match '"guild_id"\s*:\s*444444444444444444'
        $raw | Should -Not -Match '"guild_id"\s*:\s*"'
    }

    It "preserves the fields Start-BATCRelayBot needs" {
        $env = New-InstalledConfig
        $json = Update-ConfigJson -ConfigPath $env.ConfigPath -Field 'Guild' -Value "555555555555555555"
        Write-ConfigFile -ConfigPath $env.ConfigPath -JsonContent $json | Out-Null

        $config = Get-Content $env.ConfigPath -Raw | ConvertFrom-Json
        $config.python_path              | Should -Not -BeNullOrEmpty
        $config.voicemeeter_path         | Should -Not -BeNullOrEmpty
        $config.voicemeeter_process_name | Should -Not -BeNullOrEmpty
    }

    It "verifies a change by reading it back from disk" {
        $env = New-InstalledConfig
        $json = Update-ConfigJson -ConfigPath $env.ConfigPath -Field 'AudioDevice' `
            -Value "Voicemeeter Out B2 (VB-Audio Voicemeeter VAIO)"
        Write-ConfigFile -ConfigPath $env.ConfigPath -JsonContent $json | Out-Null

        (Verify-ConfigChange -ConfigPath $env.ConfigPath -Field 'AudioDevice' `
            -ExpectedValue "Voicemeeter Out B2 (VB-Audio Voicemeeter VAIO)").Verified | Should -BeTrue
    }
}

Describe "Edit-BATCRelayBotConfig end to end" {

    It "applies a channel change and reports it" {
        $env = New-InstalledConfig

        # Menu: 2 (server ID), the new ID, then confirm.
        # The editor returns to its menu after a change now, so every script
        # that drives it ends with a q. Relying on the answer list running out
        # would leave the test passing for a reason it never states.
        #
        # Driven through the server ID rather than the token or the audio
        # device: those reach the Discord API and ffmpeg respectively, and a
        # test of the editor should not depend on either being reachable.
        $script:Answers = @('2', '777777777777777777', 'y', 'q')
        $script:AnswerIndex = 0
        Mock -ModuleName BATCRelayBot Read-Host {
            $answer = $script:Answers[$script:AnswerIndex]
            $script:AnswerIndex++
            return $answer
        }

        $result = Edit-BATCRelayBotConfig -InstallPath $env.InstallPath -PassThru 6>$null

        $result.Success | Should -BeTrue -Because ($result.Errors -join '; ')
        $result.UpdatedFields.Keys | Should -Contain 'Guild'

        $config = Get-Content $env.ConfigPath -Raw | ConvertFrom-Json
        $config.guild_id | Should -Be 777777777777777777
        Test-BotCanLoad -ConfigPath $env.ConfigPath | Should -BeTrue
    }

    It "creates a backup before changing anything" {
        $env = New-InstalledConfig

        $script:Answers = @('2', '888888888888888888', 'y', 'q')
        $script:AnswerIndex = 0
        Mock -ModuleName BATCRelayBot Read-Host {
            $answer = $script:Answers[$script:AnswerIndex]
            $script:AnswerIndex++
            return $answer
        }

        $result = Edit-BATCRelayBotConfig -InstallPath $env.InstallPath -PassThru 6>$null

        $result.BackupPath | Should -Not -BeNullOrEmpty
        Test-Path $result.BackupPath | Should -BeTrue
    }

    It "changes nothing when the confirmation is declined" {
        $env = New-InstalledConfig
        $before = Get-Content $env.ConfigPath -Raw

        # Answer the confirmation with 'n', then quit the menu.
        $script:Answers = @('2', '999999999999999999', 'n', 'q')
        $script:AnswerIndex = 0
        Mock -ModuleName BATCRelayBot Read-Host {
            $answer = $script:Answers[$script:AnswerIndex]
            $script:AnswerIndex++
            return $answer
        }

        $result = Edit-BATCRelayBotConfig -InstallPath $env.InstallPath -PassThru 6>$null

        $result.Success | Should -BeFalse
        (Get-Content $env.ConfigPath -Raw) | Should -Be $before
    }

    # The point of the loop: correcting two fields used to mean running the
    # editor twice and reading the same warnings again.
    It "applies more than one change in a session" {
        $env = New-InstalledConfig

        # Twice through the same field, because it is the only one that reaches
        # neither the Discord API nor ffmpeg. What is being proved is that the
        # menu comes back and the second change is applied at all - the editor
        # used to exit after the first.
        $script:Answers = @(
            '2', '111111111111111111', 'y',
            '2', '222222222222222222', 'y',
            'q'
        )
        $script:AnswerIndex = 0
        Mock -ModuleName BATCRelayBot Read-Host {
            $answer = $script:Answers[$script:AnswerIndex]
            $script:AnswerIndex++
            return $answer
        }

        $result = Edit-BATCRelayBotConfig -InstallPath $env.InstallPath -PassThru 6>$null

        $result.Success | Should -BeTrue -Because ($result.Errors -join '; ')
        $result.UpdatedFields.Keys | Should -Contain 'Guild'

        # The second value is in the file, which a single pass cannot produce:
        # it would have stopped after writing the first.
        #
        # Counting backups would be the other proof and is not used - the file
        # name carries a whole-second timestamp, so two changes in the same
        # second write the same name.
        $config = Get-Content $env.ConfigPath -Raw | ConvertFrom-Json
        $config.guild_id | Should -Be 222222222222222222

        Test-BotCanLoad -ConfigPath $env.ConfigPath | Should -BeTrue
    }

    It "leaves the editor when the menu is quit straight away" {
        $env = New-InstalledConfig

        $script:Answers = @('q')
        $script:AnswerIndex = 0
        Mock -ModuleName BATCRelayBot Read-Host {
            $answer = $script:Answers[$script:AnswerIndex]
            $script:AnswerIndex++
            return $answer
        }

        $result = Edit-BATCRelayBotConfig -InstallPath $env.InstallPath -PassThru 6>$null

        $result.Success | Should -BeFalse
        $result.Errors  | Should -Contain "Cancelled by the user"
        $result.UpdatedFields.Count | Should -Be 0
    }
}
