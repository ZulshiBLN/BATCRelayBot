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

    It "User-Agent follows the format Discord documents: DiscordBot (url, version)" {
        # Discord specifies "DiscordBot ($url, $versionNumber)". The prefix is
        # what stops Cloudflare rejecting the request; the URL and version are
        # required by the same section of the API documentation.
        $content = Get-Content -Path "$PSScriptRoot\..\..\BATCRelayBot\Private\Get-DiscordConfiguration.ps1" -Raw
        $content | Should -Match 'DiscordBot \(https://[^,]+, '
    }
}

Describe "Token Validation - Error Classification" {
    # These four sat here as empty -Skip shells for months, each describing a
    # test nobody wrote. Their comments guessed at wordings the code does not
    # use ("Token expired or invalid" against the actual "Discord rejected the
    # token"), which is what a fixture written from memory rather than from the
    # source looks like. They assert the real messages now.
    #
    # What is being checked is what a user sees when their token does not work.
    # The 404 case is the one that earns its keep: it is the difference between
    # "something went wrong" and "you copied the wrong token from the wrong tab".

    BeforeAll {
        function New-HttpError {
            param([int]$StatusCode)
            $response = [pscustomobject]@{ StatusCode = $StatusCode }
            $exception = [System.Net.WebException]::new("The remote server returned an error: ($StatusCode).")
            $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response -Force
            [System.Management.Automation.ErrorRecord]::new($exception, 'HttpError', 'ProtocolError', $null)
        }
    }

    It "Classifies 401 as a rejected token, pointing at the developer portal" {
        Mock -ModuleName BATCRelayBot Invoke-WebRequest { throw (New-HttpError -StatusCode 401) }
        $result = Test-DiscordBotToken -Token ('A' * 30)
        $result.Valid | Should -Be $false
        $result.Error | Should -Match 'Discord rejected the token'
    }

    It "Classifies 403 as valid but unpermitted" {
        Mock -ModuleName BATCRelayBot Invoke-WebRequest { throw (New-HttpError -StatusCode 403) }
        $result = Test-DiscordBotToken -Token ('A' * 30)
        $result.Error | Should -Match 'lacks permission'
    }

    It "Classifies 404 as the wrong kind of token, not a missing endpoint" {
        Mock -ModuleName BATCRelayBot Invoke-WebRequest { throw (New-HttpError -StatusCode 404) }
        $result = Test-DiscordBotToken -Token ('A' * 30)
        $result.Error | Should -Match 'Not a bot token'
    }

    It "Classifies a timeout as unreachable, not as a bad token" {
        Mock -ModuleName BATCRelayBot Invoke-WebRequest {
            throw [System.Net.WebException]::new("The operation has timed out.")
        }
        $result = Test-DiscordBotToken -Token ('A' * 30)
        $result.Valid | Should -Be $false
        $result.Error | Should -Match 'Could not reach the Discord API'
    }

    # The code classifies six codes; the shells covered three. These are the
    # ones that tell a user to wait rather than to change anything.
    It "Classifies 429 and the 5xx codes as transient" {
        foreach ($pair in @(@{ Code = 429; Match = 'rate limiting' },
                            @{ Code = 500; Match = 'server error' },
                            @{ Code = 503; Match = 'temporarily unavailable' })) {
            Mock -ModuleName BATCRelayBot Invoke-WebRequest { throw (New-HttpError -StatusCode $pair.Code) }
            (Test-DiscordBotToken -Token ('A' * 30)).Error | Should -Match $pair.Match
        }
    }

    It "Never echoes the token back in an error message" {
        $token = 'A' * 30
        Mock -ModuleName BATCRelayBot Invoke-WebRequest {
            throw [System.Net.WebException]::new("Auth failed for Bot $token")
        }
        (Test-DiscordBotToken -Token $token).Error | Should -Not -Match ([regex]::Escape($token))
    }
}
