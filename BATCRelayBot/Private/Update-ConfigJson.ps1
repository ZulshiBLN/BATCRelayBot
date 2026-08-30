function Update-ConfigJson {
    <#
    .SYNOPSIS
    Reads config.json, updates single field, returns new JSON string.
    #>

    param(
        [string]$ConfigPath,
        [string]$Field,
        [string]$Value
    )

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

    $fieldMap = @{
        "Token"    = "token"
        "Channel"  = "channel_id"
        "Format"   = "output_format"
        "Activity" = "bot_activity"
    }

    $jsonField = $fieldMap[$Field]
    $config.$jsonField = $Value

    $json = $config | ConvertTo-Json -Depth 10

    return $json
}
