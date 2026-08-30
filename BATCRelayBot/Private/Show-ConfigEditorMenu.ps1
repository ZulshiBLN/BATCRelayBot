function Show-ConfigEditorMenu {
    <#
    .SYNOPSIS
    Displays interactive configuration editor menu.

    .PARAMETER ConfigPath
    Path to config.json file

    .OUTPUTS
    Hashtable with Field and Value when user confirms change, or $null on quit

    .EXAMPLE
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    $result = Show-ConfigEditorMenu -ConfigPath $configPath
    if ($result) {
        Write-Host "User selected $($result.Field): $($result.Value)"
    }
    #>

    param(
        [string]$ConfigPath
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Error "Config file not found: $ConfigPath"
        return $null
    }

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

    $token = $config.bot_token
    $channelId = $config.voice_channel_id
    $format = $config.output_format
    $activity = $config.bot_activity

    $tokenDisplay = if ($token -and $token.Length -gt 4) { $token.Substring($token.Length - 4) } else { "****" }

    $menuLoop = $true
    while ($menuLoop) {
        Clear-Host
        Write-Host "BATCRelayBot Configuration Editor" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Current Configuration:"
        Write-Host "1. Discord Token:       [***REDACTED***] (last 4: $tokenDisplay)"
        Write-Host "2. Channel ID:          $channelId"
        Write-Host "3. Output Format:       $format"
        Write-Host "4. Bot Activity:        $activity"
        Write-Host ""
        Write-Host "Select field to edit (1-4) or 'q' to quit: " -NoNewline

        $selection = Read-Host

        switch ($selection) {
            "1" {
                $result = Get-DiscordToken -CurrentToken $tokenDisplay
                if ($result.Valid) {
                    $confirm = Read-Host "Confirm change? (y/n)"
                    if ($confirm -eq "y") {
                        return @{
                            Field = "Token"
                            Value = $result.Value
                        }
                    }
                }
                else {
                    Write-Host "❌ $($result.Message)" -ForegroundColor Red
                    Read-Host "Press Enter to continue"
                }
            }

            "2" {
                $result = Get-DiscordChannel -CurrentChannel $channelId
                if ($result.Valid) {
                    $confirm = Read-Host "Confirm change? (y/n)"
                    if ($confirm -eq "y") {
                        return @{
                            Field = "Channel"
                            Value = $result.Value
                        }
                    }
                }
                else {
                    Write-Host "❌ $($result.Message)" -ForegroundColor Red
                    Read-Host "Press Enter to continue"
                }
            }

            "3" {
                $result = Get-OutputFormat -CurrentFormat $format
                if ($result.Valid) {
                    $confirm = Read-Host "Confirm change? (y/n)"
                    if ($confirm -eq "y") {
                        return @{
                            Field = "Format"
                            Value = $result.Value
                        }
                    }
                }
                else {
                    Write-Host "❌ $($result.Message)" -ForegroundColor Red
                    Read-Host "Press Enter to continue"
                }
            }

            "4" {
                $result = Get-BotActivity -CurrentActivity $activity
                if ($result.Valid) {
                    $confirm = Read-Host "Confirm change? (y/n)"
                    if ($confirm -eq "y") {
                        return @{
                            Field = "Activity"
                            Value = $result.Value
                        }
                    }
                }
                else {
                    Write-Host "❌ $($result.Message)" -ForegroundColor Red
                    Read-Host "Press Enter to continue"
                }
            }

            "q" {
                Write-Host "Exiting..."
                return $null
            }

            default {
                Write-Host "Invalid selection. Please select 1-4 or 'q'" -ForegroundColor Yellow
                Read-Host "Press Enter to continue"
            }
        }
    }
}
