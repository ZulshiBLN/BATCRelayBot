function Get-DiscordChannel {
    <#
    .SYNOPSIS
    Prompts for Discord channel ID with validation.

    .PARAMETER CurrentChannel
    Current channel ID for display

    .OUTPUTS
    Hashtable with properties: Value, Valid, Message, Field
    #>

    param(
        [string]$CurrentChannel
    )

    Write-Host ""
    Write-Host "Discord Channel ID"
    Write-Host "Current: $CurrentChannel"
    Write-Host ""

    $channelId = Read-Host "Enter new channel ID (or press Enter to skip)"

    if ($channelId -eq "") {
        return @{
            Value   = $null
            Valid   = $false
            Message = "Channel ID cannot be empty"
        }
    }

    if ($channelId -notmatch '^\d{17,21}$') {
        return @{
            Value   = $null
            Valid   = $false
            Message = "Channel ID must be 17-21 numeric digits (Discord Snowflake format)"
        }
    }

    return @{
        Value   = $channelId
        Valid   = $true
        Message = "Channel ID accepted"
        Field   = "Channel"
    }
}
