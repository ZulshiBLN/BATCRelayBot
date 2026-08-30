function Verify-ConfigChange {
    <#
    .SYNOPSIS
    Re-reads config.json, verifies written value matches expected.

    .PARAMETER ConfigPath
    Path to config.json

    .PARAMETER Field
    Field name: Token, Channel, Format, Activity

    .PARAMETER ExpectedValue
    Value that should be written

    .OUTPUTS
    Hashtable with properties: Verified (bool), WrittenValue, Message
    #>

    param(
        [string]$ConfigPath,
        [string]$Field,
        [string]$ExpectedValue
    )

    try {
        $written = Get-Content $ConfigPath -Raw | ConvertFrom-Json

        $fieldMap = @{
            "Token"    = "token"
            "Channel"  = "channel_id"
            "Format"   = "output_format"
            "Activity" = "bot_activity"
        }

        $jsonField = $fieldMap[$Field]
        $actualValue = $written.$jsonField

        if ($actualValue -eq $ExpectedValue) {
            return @{
                Verified     = $true
                WrittenValue = $actualValue
                Message      = "Verification passed"
            }
        }
        else {
            return @{
                Verified     = $false
                WrittenValue = $actualValue
                Message      = "Value mismatch: expected '$ExpectedValue', got '$actualValue'"
            }
        }
    }
    catch {
        return @{
            Verified     = $false
            WrittenValue = $null
            Message      = "JSON parse error: $_"
        }
    }
}
