#Requires -Version 5.1

<#
.SYNOPSIS
End-to-end contract test between installer and bot.

.DESCRIPTION
The installer writes config.json; bot.py and Start-BATCRelayBot read it.
Nothing in the test suite ever verified that these agree, which is why a
schema mismatch survived from v1.0.0 to v1.3.16 undetected:

  bot.py requires : bot_token, guild_id, voice_channel_id, audio_device_name
  installer wrote : bot_token, server_id, channel_id

This test derives the expected keys from the consumers themselves (bot.py
source and Start-BATCRelayBot source), so it keeps working when those
change. It must never be replaced by a test that hardcodes the schema.
#>

BeforeAll {
    $script:RepoRoot = Resolve-Path "$PSScriptRoot\..\.."
    $modulePath = Join-Path $script:RepoRoot "BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force

    # Parse REQUIRED_KEYS out of bot.py rather than duplicating the list here.
    $botPy = Get-Content (Join-Path $script:RepoRoot "bot.py") -Raw
    $script:BotRequiredKeys = @()
    if ($botPy -match 'REQUIRED_KEYS\s*=\s*\[(.*?)\]') {
        $script:BotRequiredKeys = ([regex]::Matches($Matches[1], '"([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value })
    }

    # Parse the required config fields out of Start-BATCRelayBot the same way.
    $starter = Get-Content (Join-Path $script:RepoRoot "BATCRelayBot\Public\Start-BATCRelayBot.ps1") -Raw
    $script:LauncherRequiredKeys = @()
    if ($starter -match '\$requiredFields\s*=\s*@\((.*?)\)') {
        $script:LauncherRequiredKeys = ([regex]::Matches($Matches[1], '"([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value })
    }

    # A representative, fully-detected environment.
    $script:Prereqs = @{
        Python      = @{ Found = $true; Path = "C:\Python312\python.exe"; Version = "Python 3.12.1" }
        FFmpeg      = @{ Found = $true; Path = "C:\ffmpeg\bin\ffmpeg.exe"; Version = "n7.1" }
        VoiceMeeter = @{
            Found       = $true
            Path        = "C:\Program Files (x86)\VB\Voicemeeter"
            ExePath     = "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter_x64.exe"
            ProcessName = "voicemeeter_x64"
        }
        BeyondATC   = @{
            Found       = $true
            Path        = "C:\Program Files\BeyondATC"
            ExePath     = "C:\Program Files\BeyondATC\BeyondATC.exe"
            ProcessName = "BeyondATC"
        }
    }

    $script:Discord = @{
        BotToken        = ("A" * 24) + "." + ("B" * 6) + "." + ("C" * 27)
        GuildId         = "123456789012345678"
        VoiceChannelId  = "987654321098765432"
        AudioDeviceName = "VoiceMeeter Output (VB-Audio Voicemeeter VAIO)"
    }
}

Describe "Config contract: installer output vs. consumers" {

    BeforeAll {
        $script:ConfigDir = Join-Path ([System.IO.Path]::GetTempPath()) "batc-contract-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
        $script:ConfigPath = Join-Path $script:ConfigDir "config.json"

        New-BotConfigFile -ConfigPath $script:ConfigPath `
            -Prerequisites $script:Prereqs -DiscordConfig $script:Discord | Out-Null

        # Read it back exactly the way bot.py does (utf-8-sig tolerant).
        $script:Config = Get-Content $script:ConfigPath -Raw -Encoding UTF8 |
            ForEach-Object { $_.TrimStart([char]0xFEFF) } | ConvertFrom-Json
    }

    AfterAll {
        Remove-Item $script:ConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "sanity: the consumers' key lists were actually parsed" {
        $script:BotRequiredKeys      | Should -Not -BeNullOrEmpty
        $script:LauncherRequiredKeys | Should -Not -BeNullOrEmpty
    }

    It "produces every key bot.py lists in REQUIRED_KEYS" {
        foreach ($key in $script:BotRequiredKeys) {
            $script:Config.PSObject.Properties.Name | Should -Contain $key
        }
    }

    It "produces every key bot.py requires as non-empty (bot.py rejects empty)" {
        foreach ($key in $script:BotRequiredKeys) {
            $script:Config.$key | Should -Not -BeNullOrEmpty -Because "bot.py exits when '$key' is falsy"
        }
    }

    It "produces every config field Start-BATCRelayBot requires" {
        foreach ($key in $script:LauncherRequiredKeys) {
            $script:Config.PSObject.Properties.Name | Should -Contain $key
        }
    }

    It "writes guild_id and voice_channel_id as JSON numbers, not strings" {
        # discord.py's get_guild()/get_channel() match on int; a quoted ID
        # silently resolves to None and the bot logs 'not found'.
        $raw = Get-Content $script:ConfigPath -Raw
        $raw | Should -Match '"guild_id"\s*:\s*\d+'
        $raw | Should -Match '"voice_channel_id"\s*:\s*\d+'
        $script:Config.guild_id        | Should -BeOfType [long]
        $script:Config.voice_channel_id | Should -BeOfType [long]
    }

    It "does not emit the legacy misnamed keys" {
        $names = $script:Config.PSObject.Properties.Name
        $names | Should -Not -Contain "server_id"
        $names | Should -Not -Contain "channel_id"
    }

    It "points voicemeeter_path at an executable, not a directory" {
        # Start-BATCRelayBot calls Start-Process -FilePath $config.voicemeeter_path
        $script:Config.voicemeeter_path | Should -Match '\.exe$'
    }

    It "writes a voicemeeter_process_name usable by Get-Process (no .exe suffix)" {
        $script:Config.voicemeeter_process_name | Should -Not -BeNullOrEmpty
        $script:Config.voicemeeter_process_name | Should -Not -Match '\.exe$'
    }

    It "is valid JSON parseable by a strict reader" {
        { Get-Content $script:ConfigPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It "writes UTF-8 without BOM" {
        $bytes = [System.IO.File]::ReadAllBytes($script:ConfigPath)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $hasBom | Should -BeFalse
    }
}

Describe "Config contract: BeyondATC is optional" {

    BeforeAll {
        $script:NoBatcDir = Join-Path ([System.IO.Path]::GetTempPath()) "batc-nobatc-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $script:NoBatcDir -Force | Out-Null
        $script:NoBatcPath = Join-Path $script:NoBatcDir "config.json"

        $prereqsNoBatc = @{}
        foreach ($k in $script:Prereqs.Keys) { $prereqsNoBatc[$k] = $script:Prereqs[$k] }
        $prereqsNoBatc.BeyondATC = @{ Found = $false; Path = $null; ExePath = $null; ProcessName = $null }

        New-BotConfigFile -ConfigPath $script:NoBatcPath `
            -Prerequisites $prereqsNoBatc -DiscordConfig $script:Discord | Out-Null

        $script:NoBatcConfig = Get-Content $script:NoBatcPath -Raw | ConvertFrom-Json
    }

    AfterAll {
        Remove-Item $script:NoBatcDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "still satisfies every bot.py required key without BeyondATC" {
        foreach ($key in $script:BotRequiredKeys) {
            $script:NoBatcConfig.$key | Should -Not -BeNullOrEmpty
        }
    }

    It "emits empty batc fields rather than omitting them" {
        # Start-BATCRelayBot treats empty as 'skip', missing as a hard error.
        $names = $script:NoBatcConfig.PSObject.Properties.Name
        $names | Should -Contain "batc_path"
        $names | Should -Contain "batc_process_name"
    }
}

Describe "Config migration from the pre-1.4.0 schema" {

    BeforeAll {
        $script:MigDir = Join-Path ([System.IO.Path]::GetTempPath()) "batc-mig-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $script:MigDir -Force | Out-Null
        $script:MigPath = Join-Path $script:MigDir "config.json"
    }

    AfterAll {
        Remove-Item $script:MigDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "renames server_id/channel_id and converts them to numbers" {
        @{
            bot_token  = "legacy-token"
            server_id  = "123456789012345678"
            channel_id = "987654321098765432"
        } | ConvertTo-Json | Set-Content $script:MigPath -Encoding UTF8

        $result = Convert-LegacyBotConfig -ConfigPath $script:MigPath

        $result.Migrated | Should -BeTrue
        $migrated = Get-Content $script:MigPath -Raw | ConvertFrom-Json
        $migrated.guild_id         | Should -Be 123456789012345678
        $migrated.voice_channel_id | Should -Be 987654321098765432
        $migrated.PSObject.Properties.Name | Should -Not -Contain "server_id"
        $migrated.PSObject.Properties.Name | Should -Not -Contain "channel_id"
    }

    It "reports a config that is already current as not migrated" {
        @{
            bot_token         = "t"
            guild_id          = 123456789012345678
            voice_channel_id  = 987654321098765432
            audio_device_name = "X"
        } | ConvertTo-Json | Set-Content $script:MigPath -Encoding UTF8

        (Convert-LegacyBotConfig -ConfigPath $script:MigPath).Migrated | Should -BeFalse
    }

    It "leaves a missing config alone without throwing" {
        $absent = Join-Path $script:MigDir "does-not-exist.json"
        { Convert-LegacyBotConfig -ConfigPath $absent } | Should -Not -Throw
    }
}
