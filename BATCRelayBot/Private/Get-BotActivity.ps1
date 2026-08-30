function Get-BotActivity {
    <#
    .SYNOPSIS
    Prompts for bot activity status text with length validation.

    .PARAMETER CurrentActivity
    Current activity text for display

    .OUTPUTS
    Hashtable with properties: Value, Valid, Message, Field
    #>

    param(
        [string]$CurrentActivity
    )

    $maxLength = 128

    Write-Host ""
    Write-Host "Bot Activity Status"
    Write-Host "Current: $CurrentActivity"
    Write-Host "Max: $maxLength characters"
    Write-Host ""

    $activity = Read-Host "Enter new activity (or press Enter to skip)"

    if ($activity -eq "") {
        return @{
            Value   = $null
            Valid   = $false
            Message = "Activity cannot be empty"
        }
    }

    $length = $activity.Length
    if ($length -gt $maxLength) {
        return @{
            Value   = $null
            Valid   = $false
            Message = "Activity too long ($length/$maxLength characters)"
        }
    }

    Write-Host "Status: $length/$maxLength characters"

    return @{
        Value   = $activity
        Valid   = $true
        Message = "Activity accepted ($length/$maxLength)"
        Field   = "Activity"
    }
}
