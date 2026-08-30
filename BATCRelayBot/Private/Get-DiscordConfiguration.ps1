#Requires -Version 5.1

function Get-DiscordConfiguration {
    param()

    Write-Host ""
    Write-Host "Discord Bot Configuration" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "Enter your bot credentials to proceed" -ForegroundColor Gray
    Write-Host ""

    $config = @{
        BotToken = $null
        ServerId = $null
        ChannelId = $null
    }

    # Step 1: Bot Token
    $tokenValid = $false
    $attempts = 0

    while (-not $tokenValid -and $attempts -lt 3) {
        Write-Host "Step 1/3: Discord Bot Token" -ForegroundColor Cyan
        Write-Host "Get token: https://discord.com/developers/applications" -ForegroundColor Gray
        $token = Read-Host "Enter Bot Token (masked)" -AsSecureString
        $tokenStr = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($token))

        if ($tokenStr.Length -lt 50) {
            Write-Host "ERROR: Token too short" -ForegroundColor Red
            $attempts++
            Write-Host ""
            continue
        }

        $validation = Test-DiscordBotToken -Token $tokenStr
        if ($validation.Valid) {
            Write-Host "Token valid. Bot: $($validation.BotName)" -ForegroundColor Green
            $config.BotToken = $tokenStr
            $tokenValid = $true
        } else {
            Write-Host "Token validation failed: $($validation.Error)" -ForegroundColor Red
            $attempts++
        }
        Write-Host ""
    }

    if (-not $tokenValid) {
        Write-Host "ERROR: Could not validate token" -ForegroundColor Red
        return $null
    }

    # Step 2: Server ID
    $serverOk = $false
    while (-not $serverOk) {
        Write-Host "Step 2/3: Discord Server ID" -ForegroundColor Cyan
        Write-Host "Enable Developer Mode, right-click server, Copy Server ID" -ForegroundColor Gray
        $id = Read-Host "Enter Server ID"

        if ($id -notmatch '^\d{18,20}$') {
            Write-Host "ERROR: Invalid format (need 18-20 digits)" -ForegroundColor Red
            Write-Host ""
            continue
        }

        $config.ServerId = $id
        Write-Host "Server ID accepted" -ForegroundColor Green
        $serverOk = $true
        Write-Host ""
    }

    # Step 3: Channel ID
    $channelOk = $false
    while (-not $channelOk) {
        Write-Host "Step 3/3: Discord Channel ID" -ForegroundColor Cyan
        Write-Host "Enable Developer Mode, right-click channel, Copy Channel ID" -ForegroundColor Gray
        $id = Read-Host "Enter Channel ID"

        if ($id -notmatch '^\d{18,20}$') {
            Write-Host "ERROR: Invalid format (need 18-20 digits)" -ForegroundColor Red
            Write-Host ""
            continue
        }

        $config.ChannelId = $id
        Write-Host "Channel ID accepted" -ForegroundColor Green
        $channelOk = $true
        Write-Host ""
    }

    return $config
}

function Test-DiscordBotToken {
    param([string]$Token)

    try {
        $headers = @{
            Authorization = "Bot $Token"
            "User-Agent" = "BATCRelayBot/1.3.11"
        }

        $uri = "https://discord.com/api/v10/users/@me"
        $response = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
        $user = $response.Content | ConvertFrom-Json

        return @{
            Valid = $true
            BotName = $user.username
            BotId = $user.id
            Error = $null
        }
    } catch {
        return @{
            Valid = $false
            BotName = $null
            BotId = $null
            Error = "Token validation failed"
        }
    }
}

Export-ModuleMember -Function Get-DiscordConfiguration, Test-DiscordBotToken
