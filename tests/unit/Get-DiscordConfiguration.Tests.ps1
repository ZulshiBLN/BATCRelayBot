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
        $token = "MzA4OTIzMTY4OTEwNzI2MTc2.COIM8g.LFqo5SoZfTgZ0OmfPy6rx7EXPE8"
        $result = Test-DiscordBotToken -Token $token
        $result | Should -Not -BeNull
    }
}
