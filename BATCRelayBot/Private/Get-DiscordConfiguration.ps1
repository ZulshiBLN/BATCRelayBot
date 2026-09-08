#Requires -Version 5.1

<#
.SYNOPSIS
Collects and validates the Discord credentials the bot needs.

.DESCRIPTION
Returns a hashtable keyed the way New-BotConfigFile expects:

    BotToken, GuildId, VoiceChannelId

The names deliberately mirror bot.py's config keys (guild_id,
voice_channel_id) rather than the Discord UI wording ("Server ID"). The old
ServerId/ChannelId naming is what let the installer write server_id and
channel_id into config.json for sixteen releases without anyone noticing
that bot.py reads neither.
#>

function Get-DiscordConfiguration {
    [OutputType([hashtable])]
    param(
        [string]$LogPath
    )

    Write-Host "Discord Configuration" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "Three values from the Discord developer portal and your server." -ForegroundColor Gray
    Write-Host ""

    $config = @{
        BotToken       = $null
        GuildId        = $null
        VoiceChannelId = $null
    }

    $token = Read-DiscordToken -LogPath $LogPath
    if (-not $token) { return $null }
    $config.BotToken = $token

    $config.GuildId = Read-DiscordSnowflake `
        -Label "Server ID (guild)" `
        -Hint "Discord: Settings > Advanced > Developer Mode, then right-click the server > Copy Server ID" `
        -LogPath $LogPath
    if (-not $config.GuildId) { return $null }

    $config.VoiceChannelId = Read-DiscordSnowflake `
        -Label "Voice channel ID" `
        -Hint "Right-click the VOICE channel the bot should join > Copy Channel ID" `
        -LogPath $LogPath
    if (-not $config.VoiceChannelId) { return $null }

    return $config
}

function Read-DiscordToken {
    <#
    .SYNOPSIS
    Prompts for the bot token and verifies it against the Discord API.

    .OUTPUTS
    The token, or $null after three failed attempts.
    #>
    [OutputType([string])]
    param([string]$LogPath)

    $maxAttempts = 3

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Write-Host "Step 1/3: Bot token" -ForegroundColor Cyan
        Write-Host "  https://discord.com/developers/applications > your app > Bot > Reset Token" -ForegroundColor Gray

        $secure = Read-Host "  Token (hidden)" -AsSecureString
        $plain = ConvertFrom-SecureStringToPlainText -Secure $secure

        if ([string]::IsNullOrWhiteSpace($plain)) {
            Write-Host "  No token entered (attempt $attempt/$maxAttempts)." -ForegroundColor Red
            Write-Host ""
            continue
        }

        if ($plain.Length -lt 50) {
            # Real bot tokens are ~59-72 characters. A short value is almost
            # always the application's Client Secret or the Application ID.
            Write-Host "  That looks too short for a bot token (attempt $attempt/$maxAttempts)." -ForegroundColor Red
            Write-Host "  Make sure you copied the Bot token, not the Client Secret or Application ID." -ForegroundColor Yellow
            Write-InstallLog "Token rejected locally: too short" -LogPath $LogPath -Level WARN
            Write-Host ""
            continue
        }

        Write-Host "  Checking the token against the Discord API..." -ForegroundColor Gray
        $validation = Test-DiscordBotToken -Token $plain

        if ($validation.Valid) {
            Write-Host "  Token accepted. Bot: $($validation.BotName)" -ForegroundColor Green
            Write-InstallLog "Token validated for bot '$($validation.BotName)'" -LogPath $LogPath
            Write-Host ""
            return $plain
        }

        Write-Host "  Rejected (attempt $attempt/$maxAttempts): $($validation.Error)" -ForegroundColor Red
        Write-InstallLog "Token validation failed: $($validation.Error)" -LogPath $LogPath -Level WARN
        Write-Host ""
    }

    Write-Host "  Token could not be validated after $maxAttempts attempts." -ForegroundColor Red
    Write-Host ""
    return $null
}

function Read-DiscordSnowflake {
    <#
    .SYNOPSIS
    Prompts for a Discord ID until it is well-formed or the user gives up.

    .OUTPUTS
    The ID as a string, or $null if the user entered nothing to abort.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Hint,
        [string]$LogPath
    )

    $step = if ($Label -like "Server*") { "Step 2/3" } else { "Step 3/3" }

    while ($true) {
        Write-Host "${step}: $Label" -ForegroundColor Cyan
        Write-Host "  $Hint" -ForegroundColor Gray
        $value = Read-Host "  $Label"

        if ([string]::IsNullOrWhiteSpace($value)) {
            Write-Host "  Nothing entered - aborting." -ForegroundColor Yellow
            Write-Host ""
            return $null
        }

        $value = $value.Trim()

        # Discord snowflakes are 17-20 digits today and grow over time, so
        # accept a slightly wider range than the current length.
        if ($value -notmatch '^\d{17,21}$') {
            Write-Host "  A Discord ID is 17-21 digits with no other characters." -ForegroundColor Red
            Write-Host "  Enable Developer Mode first, otherwise 'Copy ID' will not appear." -ForegroundColor Yellow
            Write-Host ""
            continue
        }

        Write-Host "  Accepted." -ForegroundColor Green
        Write-InstallLog "$Label accepted: $value" -LogPath $LogPath
        Write-Host ""
        return $value
    }
}

function ConvertFrom-SecureStringToPlainText {
    <#
    .SYNOPSIS
    Reads a SecureString without leaking the unmanaged buffer.

    .DESCRIPTION
    SecureStringToCoTaskMemUnicode allocates memory that the caller must free
    again; the previous implementation never did, leaving the token in
    unmanaged memory for the life of the session.
    #>
    [OutputType([string])]
    param([System.Security.SecureString]$Secure)

    if (-not $Secure) { return $null }

    $ptr = [System.IntPtr]::Zero
    try {
        $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($Secure)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
    } finally {
        if ($ptr -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeCoTaskMemUnicode($ptr)
        }
    }
}

function Test-DiscordBotToken {
    <#
    .SYNOPSIS
    Verifies a bot token against GET /users/@me.

    .DESCRIPTION
    The User-Agent must start with "DiscordBot" or Cloudflare blocks the
    request outright, which older versions surfaced as a generic connection
    failure.
    #>
    [OutputType([hashtable])]
    param([string]$Token)

    try {
        $moduleVersion = Get-ModuleVersion

        $headers = @{
            Authorization = "Bot $Token"
            "User-Agent"  = "DiscordBot (https://github.com/ZulshiBLN/BATCRelayBot, $moduleVersion)"
        }

        $response = Invoke-WebRequest -Uri "https://discord.com/api/v10/users/@me" `
            -Headers $headers -Method Get -UseBasicParsing `
            -WarningAction SilentlyContinue -ErrorAction Stop -TimeoutSec 15

        $user = $response.Content | ConvertFrom-Json

        return @{
            Valid   = $true
            BotName = $user.username
            BotId   = $user.id
            Error   = $null
        }
    } catch {
        $statusCode = 0
        if ($_.Exception.PSObject.Properties.Name -contains 'Response' -and $_.Exception.Response) {
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = 0 }
        }

        $message = switch ($statusCode) {
            401 { "Discord rejected the token. Reset it in the developer portal and copy the new one." }
            403 { "The token is valid but the bot lacks permission. Check its role and scopes." }
            404 { "Not a bot token - make sure you copied it from the Bot tab, not OAuth2." }
            429 { "Discord is rate limiting this machine. Wait a moment and try again." }
            500 { "Discord had a server error. Try again shortly." }
            503 { "The Discord API is temporarily unavailable. Try again shortly." }
            default {
                # Sanitised: the raw exception can echo the token back.
                $raw = Remove-SensitiveData -Text $_.Exception.Message
                if ($raw -match 'timed out|timeout|No such host|remote name') {
                    "Could not reach the Discord API. Check the internet connection or a proxy."
                } else {
                    "Could not reach the Discord API ($raw)"
                }
            }
        }

        return @{
            Valid   = $false
            BotName = $null
            BotId   = $null
            Error   = $message
        }
    }
}

Export-ModuleMember -Function @(
    'Get-DiscordConfiguration',
    'Test-DiscordBotToken',
    'Read-DiscordToken',
    'Read-DiscordSnowflake',
    'ConvertFrom-SecureStringToPlainText'
)
