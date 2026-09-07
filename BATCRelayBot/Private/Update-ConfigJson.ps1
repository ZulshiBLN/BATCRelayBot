#Requires -Version 5.1

function Update-ConfigJson {
    <#
    .SYNOPSIS
    Updates a single field in config.json and returns the new JSON.

    .DESCRIPTION
    Reads config.json, changes one field, and returns the modified document as
    a string. All other fields keep their values and their order.

    The field name is an editor-level name (Token, Guild, Channel,
    AudioDevice); Get-ConfigFieldMap translates it to the JSON key and the
    required type. That mapping lives in one place now, because keeping a
    private copy here is how the editor came to write `token` while the
    installer wrote `bot_token`.

    .PARAMETER ConfigPath
    Full path to config.json.

    .PARAMETER Field
    Editor field name. Unknown names throw rather than writing to nothing.

    .PARAMETER Value
    New value. Coerced to the field's declared type - Discord IDs become JSON
    numbers, not quoted strings.

    .OUTPUTS
    [string] the modified JSON.
    #>
    param(
        [string]$ConfigPath,
        [string]$Field,
        $Value
    )

    $definition = Get-ConfigFieldDefinition -Field $Field
    $jsonField = $definition.Json
    $typedValue = ConvertTo-ConfigFieldValue -Field $Field -Value $Value

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

    # ConvertFrom-Json yields a PSCustomObject, and dot-assignment on one can
    # only overwrite an existing property - it throws for a new one.
    if ($config.PSObject.Properties.Name -contains $jsonField) {
        $config.$jsonField = $typedValue
    } else {
        $config | Add-Member -NotePropertyName $jsonField -NotePropertyValue $typedValue -Force
    }

    return ($config | ConvertTo-Json -Depth 10)
}

Export-ModuleMember -Function Update-ConfigJson
