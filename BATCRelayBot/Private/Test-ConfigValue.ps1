#Requires -Version 5.1

function Test-ConfigValue {
    <#
    .SYNOPSIS
    Validates a value before it is written to config.json.

    .DESCRIPTION
    Field names come from Get-ConfigFieldMap, so the editor cannot validate a
    field it has no way to save.

    .PARAMETER Field
    Editor field name: Token, Guild, Channel or AudioDevice.

    .PARAMETER Value
    The value to check.

    .OUTPUTS
    Hashtable with Valid and Message.
    #>
    param(
        [string]$Field,
        [string]$Value
    )

    try {
        $definition = Get-ConfigFieldDefinition -Field $Field
    } catch {
        return @{ Valid = $false; Message = $_.Exception.Message }
    }

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @{ Valid = $false; Message = "$($definition.Label) cannot be empty" }
    }

    switch ($Field) {
        "Token" {
            # Real bot tokens are around 59-72 characters. Anything much
            # shorter is usually the Client Secret or the Application ID.
            if ($Value.Length -lt 24) {
                return @{ Valid = $false; Message = "Token too short - make sure you copied the Bot token, not the Client Secret" }
            }
            if ($Value -notmatch '^[a-zA-Z0-9_\-\.]+$') {
                return @{ Valid = $false; Message = "Token contains characters a Discord token never has" }
            }
            return @{ Valid = $true; Message = "Token accepted" }
        }

        { $_ -in @("Guild", "Channel") } {
            # Discord snowflakes are 17-20 digits today and grow over time.
            if ($Value -notmatch '^\d{17,21}$') {
                return @{ Valid = $false; Message = "$($definition.Label) must be 17-21 digits - enable Developer Mode to copy it" }
            }
            return @{ Valid = $true; Message = "$($definition.Label) accepted" }
        }

        "AudioDevice" {
            # Only a sanity check: the authoritative test is whether ffmpeg
            # lists the name, which Select-AudioDevice guarantees by
            # construction.
            if ($Value.Length -gt 256) {
                return @{ Valid = $false; Message = "Device name is implausibly long" }
            }
            return @{ Valid = $true; Message = "Audio device accepted" }
        }

        default {
            return @{ Valid = $false; Message = "No validator for field '$Field'" }
        }
    }
}

Export-ModuleMember -Function Test-ConfigValue
