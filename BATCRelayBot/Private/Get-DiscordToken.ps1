function Get-DiscordToken {
    <#
    .SYNOPSIS
    Prompts for Discord bot token with secure input (masked).

    .PARAMETER CurrentToken
    Last 4 digits of current token for display (e.g., "abcd")

    .OUTPUTS
    Hashtable with properties:
    - Value: The entered token (plaintext, ready for use)
    - Valid: Whether token passed validation
    - Message: Validation feedback for user
    #>

    param(
        [string]$CurrentToken = "****"
    )

    Write-Host ""
    Write-Host "Discord Bot Token"
    Write-Host "Current: [***REDACTED***] (last 4: $CurrentToken)"
    Write-Host ""

    $secureToken = Read-Host "Enter new token (or press Enter to skip)" -AsSecureString

    if ($secureToken.Length -eq 0) {
        return @{
            Value   = $null
            Valid   = $false
            Message = "Token cannot be empty"
        }
    }

    $plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($secureToken)
    )

    if ($plainToken.Length -lt 24) {
        return @{
            Value   = $null
            Valid   = $false
            Message = "Token too short (minimum 24 characters)"
        }
    }

    if ($plainToken -notmatch '^[a-zA-Z0-9_\-\.]+$') {
        return @{
            Value   = $null
            Valid   = $false
            Message = "Token contains invalid characters"
        }
    }

    return @{
        Value   = $plainToken
        Valid   = $true
        Message = "Token accepted"
        Field   = "Token"
    }
}
