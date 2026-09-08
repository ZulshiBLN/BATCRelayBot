#Requires -Version 5.1

<#
.SYNOPSIS
Tests for the configuration editor.

.DESCRIPTION
The editor was disabled from v1.3.10 to v1.4.0 because it wrote `token` while
the installer wrote `bot_token`: an edited token went into a field nothing
read, and the bot kept using the old one. The audit that found it also noted
why the tests had missed it - they built their own config fixtures using the
editor's own field names, so both sides agreed with each other and disagreed
with reality.

These tests therefore check the editor against what bot.py actually requires,
not against the editor's own idea of the schema.
#>

BeforeAll {
    Import-Module "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1" -Force

    $script:RepoRoot = Resolve-Path "$PSScriptRoot\..\.."

    # The authoritative key list, read from bot.py itself.
    $botPy = Get-Content (Join-Path $script:RepoRoot "bot.py") -Raw
    $script:BotRequiredKeys = @()
    if ($botPy -match 'REQUIRED_KEYS\s*=\s*\[(.*?)\]') {
        $script:BotRequiredKeys = ([regex]::Matches($Matches[1], '"([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value })
    }

    $script:SandboxRoot = Join-Path ([System.IO.Path]::GetTempPath()) "batc-editor-tests"

    function New-EditorSandbox {
        <# A config as the 1.4.0 installer would actually write it. #>
        $path = Join-Path $script:SandboxRoot ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        $configPath = Join-Path $path "config.json"

        [ordered]@{
            bot_token                = "AAAAAAAAAAAAAAAAAAAAAAAA.BBBBBB.CCCCCCCCCCCCCCCCCCCCCCCCCCC"
            guild_id                 = 123456789012345678
            voice_channel_id         = 987654321098765432
            audio_device_name        = "Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)"
            python_path              = "C:\Python312\python.exe"
            ffmpeg_path              = "C:\ffmpeg\bin\ffmpeg.exe"
            voicemeeter_path         = "C:\Program Files (x86)\VB\Voicemeeter\voicemeeter_x64.exe"
            voicemeeter_process_name = "voicemeeter_x64"
            voicemeeter_wait_seconds = 6
            batc_path                = ""
            batc_process_name        = ""
            batc_wait_seconds        = 8
        } | ConvertTo-Json | Set-Content $configPath -Encoding UTF8

        return $configPath
    }
}

AfterAll {
    if ($script:SandboxRoot -and (Test-Path $script:SandboxRoot)) {
        Remove-Item $script:SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Get-ConfigFieldMap" {

    It "offers only fields bot.py actually reads" {
        # output_format and bot_activity were editable before 1.4.0 and appear
        # nowhere in bot.py, so editing them changed nothing.
        $jsonKeys = (Get-ConfigFieldMap).Values | ForEach-Object { $_.Json }

        $jsonKeys | Should -Not -Contain 'output_format'
        $jsonKeys | Should -Not -Contain 'bot_activity'
    }

    It "covers every key bot.py requires" {
        $jsonKeys = (Get-ConfigFieldMap).Values | ForEach-Object { $_.Json }
        foreach ($key in $script:BotRequiredKeys) {
            $jsonKeys | Should -Contain $key -Because "bot.py exits without '$key', so it must be fixable"
        }
    }

    It "maps the token to bot_token, the name the installer writes" {
        (Get-ConfigFieldDefinition -Field 'Token').Json | Should -Be 'bot_token'
    }

    It "declares the Discord IDs as numeric" {
        (Get-ConfigFieldDefinition -Field 'Guild').Type   | Should -Be 'long'
        (Get-ConfigFieldDefinition -Field 'Channel').Type | Should -Be 'long'
    }

    It "throws on an unknown field instead of writing nowhere" {
        { Get-ConfigFieldDefinition -Field 'Nonsense' } | Should -Throw
    }
}

Describe "ConvertTo-ConfigFieldValue" {

    It "converts a Discord ID to a number" {
        $value = ConvertTo-ConfigFieldValue -Field 'Channel' -Value "987654321098765432"
        $value | Should -BeOfType [long]
    }

    It "leaves the token as text" {
        ConvertTo-ConfigFieldValue -Field 'Token' -Value "abc.def.ghi" | Should -BeOfType [string]
    }

    It "rejects a non-numeric ID" {
        { ConvertTo-ConfigFieldValue -Field 'Guild' -Value "not-an-id" } | Should -Throw
    }
}

Describe "Test-ConfigValue" {

    It "accepts a plausible token" {
        (Test-ConfigValue -Field 'Token' -Value ("A" * 60)).Valid | Should -BeTrue
    }

    It "rejects a short token as probably the client secret" {
        (Test-ConfigValue -Field 'Token' -Value "tooshort").Valid | Should -BeFalse
    }

    It "accepts a Discord snowflake" {
        (Test-ConfigValue -Field 'Channel' -Value "987654321098765432").Valid | Should -BeTrue
    }

    It "rejects a snowflake of the wrong length" {
        (Test-ConfigValue -Field 'Guild' -Value "12345").Valid | Should -BeFalse
    }

    It "rejects an empty value for every field" {
        foreach ($field in (Get-ConfigFieldMap).Keys) {
            (Test-ConfigValue -Field $field -Value "").Valid | Should -BeFalse -Because "'$field' must not be blanked"
        }
    }

    It "reports an unknown field rather than passing it" {
        (Test-ConfigValue -Field 'Format' -Value "standard").Valid | Should -BeFalse
    }
}

Describe "Update-ConfigJson" {

    It "writes the token to bot_token, not to token" {
        $configPath = New-EditorSandbox
        $json = Update-ConfigJson -ConfigPath $configPath -Field 'Token' -Value ("Z" * 60)
        $parsed = $json | ConvertFrom-Json

        $parsed.bot_token | Should -Be ("Z" * 60)
        $parsed.PSObject.Properties.Name | Should -Not -Contain 'token'
    }

    It "writes a changed channel ID as a JSON number" {
        # A quoted ID leaves discord.py unable to resolve the channel, with
        # nothing in the log but 'not found'.
        $configPath = New-EditorSandbox
        $json = Update-ConfigJson -ConfigPath $configPath -Field 'Channel' -Value "111111111111111111"

        $json | Should -Match '"voice_channel_id"\s*:\s*111111111111111111'
        $json | Should -Not -Match '"voice_channel_id"\s*:\s*"'
    }

    It "keeps every other field untouched" {
        $configPath = New-EditorSandbox
        $before = Get-Content $configPath -Raw | ConvertFrom-Json
        $after = (Update-ConfigJson -ConfigPath $configPath -Field 'Guild' -Value "222222222222222222") | ConvertFrom-Json

        $after.bot_token                | Should -Be $before.bot_token
        $after.voice_channel_id         | Should -Be $before.voice_channel_id
        $after.audio_device_name        | Should -Be $before.audio_device_name
        $after.voicemeeter_process_name | Should -Be $before.voicemeeter_process_name
    }

    It "adds a field that is absent instead of throwing" {
        # Dot-assignment on a PSCustomObject cannot create a property.
        $configPath = New-EditorSandbox
        $stripped = Get-Content $configPath -Raw | ConvertFrom-Json
        $stripped.PSObject.Properties.Remove('audio_device_name')
        $stripped | ConvertTo-Json | Set-Content $configPath -Encoding UTF8

        { Update-ConfigJson -ConfigPath $configPath -Field 'AudioDevice' -Value "Voicemeeter Out B1" } |
            Should -Not -Throw
    }

    It "refuses a field it cannot save" {
        $configPath = New-EditorSandbox
        { Update-ConfigJson -ConfigPath $configPath -Field 'Activity' -Value "flying" } | Should -Throw
    }
}

Describe "Verify-ConfigChange" {

    It "confirms a numeric ID written correctly" {
        $configPath = New-EditorSandbox
        $json = Update-ConfigJson -ConfigPath $configPath -Field 'Channel' -Value "111111111111111111"
        Write-ConfigFile -ConfigPath $configPath -JsonContent $json | Out-Null

        (Verify-ConfigChange -ConfigPath $configPath -Field 'Channel' -ExpectedValue "111111111111111111").Verified |
            Should -BeTrue -Because "the stored number and the entered string are the same ID"
    }

    It "detects a value that was not written" {
        $configPath = New-EditorSandbox
        (Verify-ConfigChange -ConfigPath $configPath -Field 'Guild' -ExpectedValue "999999999999999999").Verified |
            Should -BeFalse
    }

    It "never echoes the token in its message" {
        $configPath = New-EditorSandbox
        $result = Verify-ConfigChange -ConfigPath $configPath -Field 'Token' -ExpectedValue ("Q" * 60)

        $result.Verified | Should -BeFalse
        $result.Message  | Should -Not -Match 'Q{10}'
    }

    It "reports unreadable JSON instead of throwing" {
        $configPath = New-EditorSandbox
        Set-Content $configPath -Value "{ invalid json" -Encoding UTF8

        $result = Verify-ConfigChange -ConfigPath $configPath -Field 'Guild' -ExpectedValue "123456789012345678"
        $result.Verified | Should -BeFalse
        $result.Message  | Should -Not -BeNullOrEmpty
    }
}

Describe "Editing keeps the config loadable by bot.py" {

    It "leaves every required key present and non-empty after each edit" {
        # The contract that matters: whatever the editor touches, the bot must
        # still start afterwards.
        $edits = @(
            @{ Field = 'Token';       Value = ("Y" * 60) },
            @{ Field = 'Guild';       Value = "222222222222222222" },
            @{ Field = 'Channel';     Value = "333333333333333333" },
            @{ Field = 'AudioDevice'; Value = "Voicemeeter Out B2 (VB-Audio Voicemeeter VAIO)" }
        )

        foreach ($edit in $edits) {
            $configPath = New-EditorSandbox
            $json = Update-ConfigJson -ConfigPath $configPath -Field $edit.Field -Value $edit.Value
            Write-ConfigFile -ConfigPath $configPath -JsonContent $json | Out-Null

            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            foreach ($key in $script:BotRequiredKeys) {
                $config.$key | Should -Not -BeNullOrEmpty -Because "'$key' must survive editing $($edit.Field)"
            }
        }
    }

    It "keeps the IDs numeric after an unrelated edit" {
        $configPath = New-EditorSandbox
        $json = Update-ConfigJson -ConfigPath $configPath -Field 'Token' -Value ("W" * 60)
        Write-ConfigFile -ConfigPath $configPath -JsonContent $json | Out-Null

        $raw = Get-Content $configPath -Raw
        $raw | Should -Match '"guild_id"\s*:\s*\d+'
        $raw | Should -Match '"voice_channel_id"\s*:\s*\d+'
    }
}

Describe "Backup-ConfigFile" {

    It "restricts the backup the way config.json is restricted" {
        # A backup holds the token in plaintext; up to ten of them used to sit
        # next to the protected original with inherited permissions.
        $configPath = New-EditorSandbox
        $backup = Backup-ConfigFile -ConfigPath $configPath

        Test-Path $backup | Should -BeTrue
        (Get-Acl $backup).AreAccessRulesProtected | Should -BeTrue
    }

    It "returns a path that still contains the original content" {
        $configPath = New-EditorSandbox
        $backup = Backup-ConfigFile -ConfigPath $configPath

        (Get-Content $backup -Raw) | Should -Be (Get-Content $configPath -Raw)
    }
}

Describe "Show-ConfigEditorMenu" {

    It "labels an unset value rather than printing nothing" {
        Format-ConfigValue $null | Should -Be "(not set)"
        Format-ConfigValue ""    | Should -Be "(not set)"
    }

    It "passes a real value through unchanged" {
        Format-ConfigValue 123456789012345678 | Should -Be "123456789012345678"
    }

    It "returns null when the user quits" {
        $configPath = New-EditorSandbox
        Mock -ModuleName BATCRelayBot Read-Host { "q" }

        Show-ConfigEditorMenu -ConfigPath $configPath 6>$null | Should -BeNullOrEmpty
    }

    It "reports a missing config instead of throwing" {
        $absent = Join-Path ([System.IO.Path]::GetTempPath()) "no-such-config-$([guid]::NewGuid()).json"

        { Show-ConfigEditorMenu -ConfigPath $absent 6>$null } | Should -Not -Throw
        Show-ConfigEditorMenu -ConfigPath $absent 6>$null | Should -BeNullOrEmpty
    }

    It "never prints any part of the token" {
        $source = Get-Content "$PSScriptRoot\..\..\BATCRelayBot\Private\Show-ConfigEditorMenu.ps1" -Raw
        # The old menu showed the last four characters of the live token.
        $source | Should -Not -Match 'Substring'
        $source | Should -Match '\[REDACTED\]'
    }
}

Describe "Edit-BATCRelayBotConfig" {

    It "is no longer disabled" {
        $source = Get-Content "$PSScriptRoot\..\..\BATCRelayBot\Public\Edit-BATCRelayBotConfig.ps1" -Raw
        $source | Should -Not -Match 'not available'
    }

    It "initialises the collections it writes into" {
        # $errors.Add and $updatedFields[...] were both used without ever
        # being created, so the function threw on whichever path it took.
        $source = Get-Content "$PSScriptRoot\..\..\BATCRelayBot\Public\Edit-BATCRelayBotConfig.ps1" -Raw
        $source | Should -Match '\$errors\s*=\s*\[System\.Collections\.ArrayList\]'
        $source | Should -Match '\$updatedFields\s*=\s*@\{\}'
    }

    It "reports a missing installation without throwing" {
        $absent = Join-Path ([System.IO.Path]::GetTempPath()) "batc-absent-$([guid]::NewGuid())"
        $result = Edit-BATCRelayBotConfig -InstallPath $absent -PassThru 6>$null

        $result.Success | Should -BeFalse
        $result.Errors  | Should -Not -BeNullOrEmpty
    }

    It "returns a cancellation result when the user quits the menu" {
        $configPath = New-EditorSandbox
        $installPath = Split-Path $configPath -Parent
        Mock -ModuleName BATCRelayBot Read-Host { "q" }

        $result = Edit-BATCRelayBotConfig -InstallPath $installPath -PassThru 6>$null

        $result.Success | Should -BeFalse
        $result.Errors  | Should -Contain "Cancelled by the user"
    }
}
