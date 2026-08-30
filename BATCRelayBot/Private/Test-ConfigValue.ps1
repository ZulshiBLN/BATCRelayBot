function Test-ConfigValue {
    <#
    .SYNOPSIS
    Routes config value validation to appropriate validator function.

    .PARAMETER Field
    Field name: Token, Channel, Format, or Activity

    .PARAMETER Value
    Value to validate

    .OUTPUTS
    Hashtable with properties: Valid, Message
    #>

    param(
        [string]$Field,
        [string]$Value
    )

    switch ($Field) {
        "Token" {
            if ($Value.Length -lt 24) {
                return @{
                    Valid   = $false
                    Message = "Token too short (minimum 24 characters)"
                }
            }
            if ($Value -notmatch '^[a-zA-Z0-9_\-\.]+$') {
                return @{
                    Valid   = $false
                    Message = "Token contains invalid characters"
                }
            }
            return @{
                Valid   = $true
                Message = "Token valid"
            }
        }

        "Channel" {
            if ($Value -notmatch '^\d{17,21}$') {
                return @{
                    Valid   = $false
                    Message = "Channel must be 17-21 numeric digits"
                }
            }
            return @{
                Valid   = $true
                Message = "Channel valid"
            }
        }

        "Format" {
            if ($Value -notin @("standard", "compact", "verbose")) {
                return @{
                    Valid   = $false
                    Message = "Format must be: standard, compact, or verbose"
                }
            }
            return @{
                Valid   = $true
                Message = "Format valid"
            }
        }

        "Activity" {
            if ($Value.Length -gt 128) {
                return @{
                    Valid   = $false
                    Message = "Activity text too long (max 128 characters)"
                }
            }
            return @{
                Valid   = $true
                Message = "Activity valid"
            }
        }

        default {
            return @{
                Valid   = $false
                Message = "Unknown field: $Field"
            }
        }
    }
}
