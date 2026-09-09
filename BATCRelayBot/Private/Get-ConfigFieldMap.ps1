#Requires -Version 5.1

<#
.SYNOPSIS
The single definition of which config fields the editor may change.

.DESCRIPTION
This map used to be written out separately in Update-ConfigJson,
Verify-ConfigChange, Test-ConfigValue and Show-ConfigEditorMenu. They drifted:
the installer wrote `bot_token` while the editor read and wrote `token`, so
an edited token was saved to a field nothing read, and the bot kept using the
old one. Keeping one definition is what stops that recurring.

Only fields bot.py actually consumes are listed. `output_format` and
`bot_activity` were editable in earlier versions but appear nowhere in
bot.py, so editing them changed nothing. `voice_channel_id` left for the same
reason: the bot joins the channel the caller is in, or one named in
`!BATCjoin`, so a channel fixed at install time decided nothing.

Type matters as much as the name: since 1.4.0 the Discord IDs are JSON
numbers. Writing one back as a string leaves the bot unable to resolve the
guild or channel, with nothing in the log but "not found".
#>

function Get-ConfigFieldMap {
    <#
    .OUTPUTS
    Ordered hashtable: editor field name -> @{ Json; Type; Label; Hint }
    #>
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    return [ordered]@{
        Token = @{
            Json  = 'bot_token'
            Type  = 'string'
            Label = 'Bot token'
            Hint  = 'https://discord.com/developers/applications > your app > Bot > Reset Token'
        }
        Guild = @{
            Json  = 'guild_id'
            Type  = 'long'
            Label = 'Server ID'
            Hint  = 'Enable Developer Mode, then right-click the server > Copy Server ID'
        }
        AudioDevice = @{
            Json  = 'audio_device_name'
            Type  = 'string'
            Label = 'Audio device'
            Hint  = 'The VoiceMeeter bus the bot captures, exactly as ffmpeg names it'
        }
    }
}

function Get-ConfigFieldDefinition {
    <#
    .SYNOPSIS
    Looks up one field, throwing on an unknown name rather than writing
    silently to $null.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][string]$Field
    )

    $map = Get-ConfigFieldMap
    if (-not $map.Contains($Field)) {
        throw "Unknown config field '$Field'. Known fields: $($map.Keys -join ', ')"
    }
    return $map[$Field]
}

function ConvertTo-ConfigFieldValue {
    <#
    .SYNOPSIS
    Coerces a value to the type its config field requires.

    .DESCRIPTION
    Everything arrives from Read-Host as a string. A field typed 'long' has to
    reach ConvertTo-Json as a number, otherwise the ID is quoted and
    discord.py resolves nothing.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Field,
        $Value
    )

    $definition = Get-ConfigFieldDefinition -Field $Field

    if ($definition.Type -eq 'long') {
        $text = ([string]$Value).Trim()
        if ($text -notmatch '^\d+$') {
            throw "$($definition.Label) must be numeric, got '$Value'"
        }
        return [long]::Parse($text)
    }

    return [string]$Value
}

Export-ModuleMember -Function @(
    'Get-ConfigFieldMap',
    'Get-ConfigFieldDefinition',
    'ConvertTo-ConfigFieldValue'
)
