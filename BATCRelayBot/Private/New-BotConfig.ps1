#Requires -Version 5.1

<#
.SYNOPSIS
Builds and writes config.json in the schema the bot and launcher actually read.

.DESCRIPTION
Single source of truth for the config file layout. Two consumers depend on it:

  bot.py                : bot_token, guild_id, audio_device_name
  Start-BATCRelayBot    : python_path, voicemeeter_path, voicemeeter_process_name,
                          batc_path, batc_process_name

Before 1.4.0 the installer wrote server_id/channel_id and never wrote
audio_device_name at all, so no installed bot could start. Any change here
must keep tests/unit/ConfigContract.Tests.ps1 green - that test derives the
expected keys from the consumers themselves.
#>

function New-BotConfigFile {
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Prerequisites,

        [Parameter(Mandatory = $true)]
        [hashtable]$DiscordConfig
    )

    # Discord IDs must be JSON numbers: discord.py matches guilds and channels
    # on int, and a quoted ID resolves to None with only a 'not found' log line.
    $guildId = [long]::Parse($DiscordConfig.GuildId)

    $vm = $Prerequisites.VoiceMeeter
    $batc = $Prerequisites.BeyondATC

    # Empty rather than absent: Start-BATCRelayBot skips an empty optional
    # component but treats a missing field as a hard error.
    $config = [ordered]@{
        bot_token                 = $DiscordConfig.BotToken
        guild_id                  = $guildId
        audio_device_name         = $DiscordConfig.AudioDeviceName

        python_path               = if ($Prerequisites.Python.Found) { $Prerequisites.Python.Path } else { "" }
        ffmpeg_path               = if ($Prerequisites.FFmpeg.Found) { $Prerequisites.FFmpeg.Path } else { "" }

        voicemeeter_path          = if ($vm.Found -and $vm.ExePath) { $vm.ExePath } else { "" }
        voicemeeter_process_name  = if ($vm.Found -and $vm.ProcessName) { $vm.ProcessName } else { "" }
        voicemeeter_wait_seconds  = 6

        batc_path                 = if ($batc.Found -and $batc.ExePath) { $batc.ExePath } else { "" }
        batc_process_name         = if ($batc.Found -and $batc.ProcessName) { $batc.ProcessName } else { "" }
        batc_wait_seconds         = 8
    }

    $json = $config | ConvertTo-Json -Depth 5
    Write-ConfigFile -ConfigPath $ConfigPath -JsonContent $json | Out-Null
    Protect-BotConfigFile -ConfigPath $ConfigPath | Out-Null

    return @{
        Success    = $true
        ConfigPath = $ConfigPath
        Config     = $config
    }
}

function Protect-BotConfigFile {
    <#
    .SYNOPSIS
    Restricts config.json to the current user (it holds the bot token).

    .DESCRIPTION
    Non-fatal by design: on a machine where ACLs cannot be set (network path,
    unusual policy) the installation should still complete. Returns whether
    the restriction was applied so the caller can log it.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    try {
        # -ErrorAction Stop so a missing file is handled by the catch instead
        # of writing a Get-Acl error into the caller's error stream.
        $acl = Get-Acl -Path $ConfigPath -ErrorAction Stop
        $acl.SetAccessRuleProtection($true, $false)

        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        if (-not $currentUser) { return $false }

        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $currentUser, 'FullControl', 'Allow')
        $acl.SetAccessRule($rule)
        Set-Acl -Path $ConfigPath -AclObject $acl -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Convert-LegacyBotConfig {
    <#
    .SYNOPSIS
    Migrates a pre-1.4.0 config.json to the schema the bot can read.

    .DESCRIPTION
    Renames server_id -> guild_id and converts it to a JSON number. Fields
    that the old installer never wrote (notably audio_device_name) cannot be
    invented here; the caller is responsible for collecting them.

    channel_id is left where it is. It used to be renamed to
    voice_channel_id, which nothing reads any more - migrating a value into a
    field no consumer looks at is work that appears to have done something.
    An old config keeps the key, unused, and the bot ignores it.

    Returns Migrated=$false when there is nothing to do, including when the
    file is absent or unreadable - migration must never block an install.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $result = @{ Migrated = $false; Changes = @(); Error = $null }

    if (-not (Test-Path $ConfigPath)) { return $result }

    try {
        $raw = Get-Content $ConfigPath -Raw -ErrorAction Stop
        $existing = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $result.Error = "config.json could not be parsed: $($_.Exception.Message)"
        return $result
    }

    $names = @($existing.PSObject.Properties.Name)
    $migrated = [ordered]@{}
    $changes = @()

    foreach ($prop in $existing.PSObject.Properties) {
        switch ($prop.Name) {
            'server_id' {
                if ($names -notcontains 'guild_id') {
                    $migrated['guild_id'] = ConvertTo-DiscordId $prop.Value
                    $changes += "server_id -> guild_id"
                }
            }
            default {
                $migrated[$prop.Name] = $prop.Value
            }
        }
    }

    # A quoted ID is as broken as a misnamed one - normalise it too.
    if ($migrated.Contains('guild_id') -and $migrated['guild_id'] -is [string]) {
        $converted = ConvertTo-DiscordId $migrated['guild_id']
        if ($null -ne $converted) {
            $migrated['guild_id'] = $converted
            $changes += "guild_id converted from string to number"
        }
    }

    if ($changes.Count -eq 0) { return $result }

    try {
        $json = $migrated | ConvertTo-Json -Depth 5
        Write-ConfigFile -ConfigPath $ConfigPath -JsonContent $json | Out-Null
        Protect-BotConfigFile -ConfigPath $ConfigPath | Out-Null
    } catch {
        $result.Error = "config.json could not be rewritten: $($_.Exception.Message)"
        return $result
    }

    $result.Migrated = $true
    $result.Changes = $changes
    return $result
}

function ConvertTo-DiscordId {
    <#
    .SYNOPSIS
    Converts a Discord snowflake to [long], or returns it unchanged if it is
    not a plain numeric string.
    #>
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [long] -or $Value -is [int]) { return [long]$Value }

    $text = [string]$Value
    if ($text -match '^\d{15,25}$') { return [long]::Parse($text) }

    return $Value
}

Export-ModuleMember -Function @(
    'New-BotConfigFile',
    'Protect-BotConfigFile',
    'Convert-LegacyBotConfig',
    'ConvertTo-DiscordId'
)
