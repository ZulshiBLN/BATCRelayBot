# The defect from Michel's end-to-end run on 2026-09-08:
#
#     [3/5] Removing the installation directory
#             FAILED: The process cannot access the file 'bot_error.log'
#                     because it is being used by another process.
#     [4/5] Cleaning up leftovers
#             Nothing to clean up.
#
# Two faults in four lines. The removal gave up after a single attempt, on a
# handle that the bot had only just released and Windows had not yet let go of.
# And the step after it looked at a different directory entirely, so it reported
# a tidy machine directly underneath a failure - then the summary said
# Success: False in a block that had been asked to go away.
#
# Both directions are covered here: a lock that never clears must be reported
# and named, and a lock that clears must not be fatal.

BeforeAll {
    Import-Module "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1" -Force

    function New-Sandbox {
        $path = Join-Path $env:TEMP ("uninstall-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $path 'logs') -Force | Out-Null
        "bot"    | Set-Content (Join-Path $path 'bot.py')
        "config" | Set-Content (Join-Path $path 'config.json')
        "log"    | Set-Content (Join-Path $path 'logs\bot_error.log')
        $path
    }
}

Describe "A file that will not go" {

    It "is named, not silently survived" {
        $sandbox = New-Sandbox
        $locked = Join-Path $sandbox 'logs\bot_error.log'

        # FileShare.None is what a running process holding its log looks like.
        $handle = [System.IO.File]::Open($locked, 'Open', 'Read', 'None')
        try {
            $result = Remove-BotContent -BotPath $sandbox -Keep 'uninstall.log' `
                -Attempts 2 -WaitMilliseconds 50

            $result.Blocked.Count | Should -BeGreaterThan 0
            $result.Blocked[0].Reason | Should -Match 'another process'
            $result.Deleted | Should -Contain 'bot.py'
            $result.Deleted | Should -Not -Contain 'bot_error.log'
        } finally {
            $handle.Close()
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "does not stop the rest of the removal" {
        $sandbox = New-Sandbox
        $handle = [System.IO.File]::Open((Join-Path $sandbox 'logs\bot_error.log'), 'Open', 'Read', 'None')
        try {
            Remove-BotContent -BotPath $sandbox -Keep 'uninstall.log' -Attempts 2 -WaitMilliseconds 50 | Out-Null
            Test-Path (Join-Path $sandbox 'config.json') | Should -Be $false
        } finally {
            $handle.Close()
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "A handle that clears" {

    # Deterministic rather than timed: the removal is made to fail twice and
    # then succeed, which is the shape of a handle being released while the
    # uninstaller waits. A test that raced a real background process would be
    # the kind that fails once a month for no reason anybody can reproduce.
    It "succeeds on a later attempt instead of giving up on the first" {
        InModuleScope BATCRelayBot {
            $sandbox = Join-Path $env:TEMP ("uninstall-retry-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
            "x" | Set-Content (Join-Path $sandbox 'bot.py')

            $script:tries = 0
            Mock Remove-Item {
                $script:tries++
                if ($script:tries -lt 3) {
                    throw "The process cannot access the file because it is being used by another process."
                }
                [System.IO.File]::Delete($Path)
            } -ParameterFilter { $Path -like '*bot.py' }

            try {
                $result = Remove-BotContent -BotPath $sandbox -Keep 'uninstall.log' `
                    -Attempts 5 -WaitMilliseconds 1

                $script:tries | Should -Be 3
                $result.Blocked.Count | Should -Be 0
                $result.Deleted | Should -Contain 'bot.py'
            } finally {
                Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "What the uninstaller reports afterwards" {

    It "names what is left instead of claiming there is nothing to clean up" {
        $sandbox = New-Sandbox
        $handle = [System.IO.File]::Open((Join-Path $sandbox 'logs\bot_error.log'), 'Open', 'Read', 'None')
        try {
            $out = ((Invoke-SecureUninstall -BotPath $sandbox -DependencyChoices @{} `
                        -LogDirectory $sandbox 6>&1) | ForEach-Object { "$_" }) -join "`n"

            $out | Should -Match 'Still present'
            $out | Should -Match 'bot_error\.log'
            $out | Should -Not -Match 'Nothing left behind'
        } finally {
            $handle.Close()
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "does not call a partial removal a success" {
        $sandbox = New-Sandbox
        $handle = [System.IO.File]::Open((Join-Path $sandbox 'logs\bot_error.log'), 'Open', 'Read', 'None')
        try {
            $result = Invoke-SecureUninstall -BotPath $sandbox -DependencyChoices @{} `
                -LogDirectory $sandbox 6>$null

            $result.Success | Should -Be $false
            $result.Leftovers | Should -Not -BeNullOrEmpty
        } finally {
            $handle.Close()
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "keeps its log in the installation directory" {
        $sandbox = New-Sandbox
        try {
            $result = Invoke-SecureUninstall -BotPath $sandbox -DependencyChoices @{} `
                -LogDirectory $sandbox 6>$null

            $result.LogPath | Should -Be (Join-Path $sandbox 'uninstall.log')
            Test-Path $result.LogPath | Should -Be $true

            # The log is the only thing that may survive.
            @(Get-ChildItem $sandbox -Recurse -File).Name | Should -Be @('uninstall.log')
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
