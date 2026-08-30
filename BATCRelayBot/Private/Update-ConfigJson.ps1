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
    $config.$jsonField = $Value

    $json = $config | ConvertTo-Json -Depth 10

    return $json
}
