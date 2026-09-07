#Requires -Version 5.1

<#
.SYNOPSIS
Tests for Get-BATCRelayBotStatus.

.DESCRIPTION
The status command used to answer purely from bot.pid. When that file was
missing or stale it reported "NOT RUNNING" while the bot was very much
running and rejoining the voice channel - the same lie Stop-BATCRelayBot told,
which is what made a live bot look unstoppable.
#>

BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force

    $script:SandboxRoot = Join-Path ([System.IO.Path]::GetTempPath()) "batc-status-tests"

    function New-StatusSandbox {
        $path = Join-Path $script:SandboxRoot ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        return $path
    }
}

AfterAll {
    if ($script:SandboxRoot -and (Test-Path $script:SandboxRoot)) {
        Remove-Item $script:SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Get-BATCRelayBotStatus" {

    It "reports not running for a path with no installation" {
        $absent = Join-Path ([System.IO.Path]::GetTempPath()) "batc-absent-$([guid]::NewGuid())"
        $status = Get-BATCRelayBotStatus -BotPath $absent 6>$null

        $status.IsRunning | Should -BeFalse
        $status.ProcessId | Should -BeNullOrEmpty
    }

    It "does not throw on a stale bot.pid" {
        $sandbox = New-StatusSandbox
        # A PID that is almost certainly not a live process.
        Set-Content -Path (Join-Path $sandbox "bot.pid") -Value "999999" -Encoding ASCII

        { Get-BATCRelayBotStatus -BotPath $sandbox 6>$null } | Should -Not -Throw

        $status = Get-BATCRelayBotStatus -BotPath $sandbox 6>$null
        $status.IsRunning | Should -BeFalse
    }

    It "does not throw on a corrupt bot.pid" {
        $sandbox = New-StatusSandbox
        Set-Content -Path (Join-Path $sandbox "bot.pid") -Value "not-a-number" -Encoding ASCII

        { Get-BATCRelayBotStatus -BotPath $sandbox 6>$null } | Should -Not -Throw
    }

    It "exposes OrphanedFromPidFile so a rediscovered bot is visible" {
        $sandbox = New-StatusSandbox
        $status = Get-BATCRelayBotStatus -BotPath $sandbox 6>$null

        $status.PSObject.Properties.Name | Should -Contain "OrphanedFromPidFile"
    }

    It "falls back to process detection instead of trusting bot.pid alone" {
        $source = Get-Content "$PSScriptRoot\..\..\BATCRelayBot\Public\Get-BATCRelayBotStatus.ps1" -Raw
        $code = [regex]::Replace($source, '<#.*?#>', '', 'Singleline')
        $code = ($code -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"

        $code | Should -Match 'Find-BotProcess'
    }
}
