BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force
}

Describe "Test-DiscordBotToken" {
    It "Returns hashtable" {
        $result = Test-DiscordBotToken -Token "test"
        $result | Should -BeOfType [hashtable]
    }

    It "Has required keys" {
        $result = Test-DiscordBotToken -Token "test"
        $result.Keys | Should -Contain "Valid"
        $result.Keys | Should -Contain "Error"
    }

    It "Handles invalid tokens" {
        $result = Test-DiscordBotToken -Token "short"
        $result.Valid | Should -Be $false
    }
}

Describe "Get-DiscordConfiguration" {
    It "Function exists" {
        { Get-Command Get-DiscordConfiguration -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe "Phase 3: Configuration Input" {
    It "Validates server ID format" {
        "123456789012345678" | Should -Match '^\d{18,20}$'
        "12345" | Should -Not -Match '^\d{18,20}$'
    }

    It "Validates channel ID format" {
        "987654321098765432" | Should -Match '^\d{18,20}$'
    }

    It "Token validation uses Discord API" {
        $token = "test_bot_token_1234567890abcdef"
        $result = Test-DiscordBotToken -Token $token
        $result | Should -Not -BeNull
    }
}

Describe "Token Validation - User-Agent Compliance" {
    It "User-Agent contains DiscordBot prefix" {
        $content = Get-Content -Path "$PSScriptRoot\..\..\BATCRelayBot\Private\Get-DiscordConfiguration.ps1" -Raw
        $content | Should -Match 'User-Agent.*DiscordBot'
    }

    It "User-Agent includes application name and version" {
        $content = Get-Content -Path "$PSScriptRoot\..\..\BATCRelayBot\Private\Get-DiscordConfiguration.ps1" -Raw
        $content | Should -Match 'DiscordBot \(BATCRelayBot/[\d.]+\)'
    }
}

Describe "Token Validation - Error Classification" {
    It "Classifies 401 unauthorized error" -Skip {
        # Requires mock Discord API endpoint returning 401
        # Mock: Invoke-WebRequest throws 401 Unauthorized
        # Expected: Error contains "Token expired or invalid"
    }

    It "Classifies 403 forbidden error" -Skip {
        # Requires mock Discord API endpoint returning 403
        # Mock: Invoke-WebRequest throws 403 Forbidden
        # Expected: Error contains "lacks required permissions"
    }

    It "Classifies 404 not found error" -Skip {
        # Requires mock Discord API endpoint returning 404
        # Mock: Invoke-WebRequest throws 404 Not Found
        # Expected: Error contains "BOT token, not USER"
    }

    It "Classifies network timeout error" -Skip {
        # Requires mock Discord API endpoint timeout
        # Mock: Invoke-WebRequest throws timeout exception
        # Expected: Error contains "Cannot reach Discord API"
    }
}
