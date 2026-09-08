#Requires -Version 5.1

function Get-DiscordToken {
    <#
    .SYNOPSIS
    Prompts for a new bot token, masked, and checks it against Discord.

    .DESCRIPTION
    The installer verifies a token against GET /users/@me before accepting it;
    the editor did not, so a dead or mistyped token could be saved and the
    failure only surfaced later as a bot that would not log in. It is verified
    here too, with the option to save anyway when the API cannot be reached -
    an offline machine should not block a legitimate edit.

    .PARAMETER SkipValidation
    Accept the token without contacting Discord. For tests.

    .OUTPUTS
    Hashtable with Value, Valid, Message, Field.
    #>
    param(
        [switch]$SkipValidation
    )

    Write-Host ""
    Write-Host "Bot token" -ForegroundColor Cyan
    # The current token is never shown, not even partially: the console
    # scrollback outlives this command and tends to end up in bug reports.
    Write-Host "  Current: [REDACTED]" -ForegroundColor Gray
    Write-Host "  $((Get-ConfigFieldDefinition -Field 'Token').Hint)" -ForegroundColor Gray
    Write-Host ""

    $secureToken = Read-Host "  New token (hidden, Enter to cancel)" -AsSecureString

    if (-not $secureToken -or $secureToken.Length -eq 0) {
        return @{ Value = $null; Valid = $false; Message = "Cancelled - token unchanged" }
    }

    $plainToken = ConvertFrom-SecureStringToPlainText -Secure $secureToken

    $check = Test-ConfigValue -Field "Token" -Value $plainToken
    if (-not $check.Valid) {
        return @{ Value = $null; Valid = $false; Message = $check.Message }
    }

    if ($SkipValidation) {
        return @{ Value = $plainToken; Valid = $true; Message = "Token accepted"; Field = "Token" }
    }

    Write-Host "  Checking the token against the Discord API..." -ForegroundColor Gray
    $validation = Test-DiscordBotToken -Token $plainToken

    if ($validation.Valid) {
        Write-Host "  Accepted. Bot: $($validation.BotName)" -ForegroundColor Green
        return @{ Value = $plainToken; Valid = $true; Message = "Token verified"; Field = "Token" }
    }

    Write-Host "  Discord rejected it: $($validation.Error)" -ForegroundColor Red
    Write-Host ""
    $anyway = Read-Host "  Save it anyway? (y/N)"

    if ($anyway -match '^(y|yes|j|ja)$') {
        return @{
            Value   = $plainToken
            Valid   = $true
            Message = "Token saved without verification"
            Field   = "Token"
        }
    }

    return @{ Value = $null; Valid = $false; Message = $validation.Error }
}

Export-ModuleMember -Function Get-DiscordToken
