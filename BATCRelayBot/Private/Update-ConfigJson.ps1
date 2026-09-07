function Update-ConfigJson {
    <#
    .SYNOPSIS
    Updates a single field in JSON configuration.

    .DESCRIPTION
    Reads config.json, updates one field, returns modified JSON string.
    Preserves all other fields and structure.

    .PARAMETER ConfigPath
    Full path to config.json file to read.

    .PARAMETER Field
    Field name to update (Token, Channel, Format, Activity).

    .PARAMETER Value
    New value for the field (validated before use).

    .OUTPUTS
    [string] Modified JSON content as string

    .EXAMPLE
    $newJson = Update-ConfigJson -ConfigPath 'C:\BATCRelayBot\config.json' `
                                 -Field 'Token' -Value 'newtoken123'
    Write-ConfigFile -ConfigPath 'C:\BATCRelayBot\config.json' -JsonContent $newJson

    .NOTES
    - Field Mapping:
      * Token -> token (bot auth token)
      * Channel -> channel_id (Discord channel ID)
      * Format -> output_format (message format type)
      * Activity -> bot_activity (status message)
    - Validation: Caller must validate value before calling
    - Error handling: Throws on JSON parse error or missing file
    #>

    param(
        [string]$ConfigPath,
        [string]$Field,
        [string]$Value
    )

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

    $fieldMap = @{
        "Token"    = "bot_token"
        "Channel"  = "voice_channel_id"
        "Format"   = "output_format"
        "Activity" = "bot_activity"
    }

    $jsonField = $fieldMap[$Field]
    if (-not $jsonField) {
        throw "Unknown field '$Field'. Expected one of: $($fieldMap.Keys -join ', ')"
    }

    # ConvertFrom-Json yields a PSCustomObject, and dot-assignment on one can
    # only overwrite an existing property - it throws for a new one. A config
    # that has never had this field (output_format and bot_activity are not
    # written by the installer) therefore needs Add-Member instead.
    if ($config.PSObject.Properties.Name -contains $jsonField) {
        $config.$jsonField = $Value
    } else {
        $config | Add-Member -NotePropertyName $jsonField -NotePropertyValue $Value -Force
    }

    $json = $config | ConvertTo-Json -Depth 10

    return $json
}
