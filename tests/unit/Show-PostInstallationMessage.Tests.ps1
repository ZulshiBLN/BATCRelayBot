# The closing message is the last thing a user reads, and it had grown to 98
# lines: success announced three times, four troubleshooting recipes that belong
# in the documentation, and two competing "next steps" lists.
#
# It also returned a hashtable nothing consumed while being called without
# Out-Null, so those fields printed on top of the installer's own result. That
# is why the dump after an install showed every key twice.
#
# The old tests here asserted that hashtable, which pinned the defect in place:
# three of them only checked the call did not throw, and four required the very
# return value that was the bug.

BeforeAll {
    $ModuleRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'BATCRelayBot'
    Import-Module (Join-Path $ModuleRoot 'BATCRelayBot.psd1') -Force

    # Deliberately not nested inside one another. The real config and log sit
    # under the install directory, so counting occurrences of the install path
    # found it three times and reported a duplicate the output does not have.
    $Install = 'C:\Fixture\InstallDirectory'
    $Config  = 'C:\Fixture\ConfigFile\config.json'
    $Log     = 'C:\Fixture\LogFile\install.log'

    # The function is private, so it is reached through the module scope rather
    # than through an export.
    #
    # Write-Host writes to the information stream. 2>&1 captures nothing here -
    # that shape has produced tests that could not fail in this repository.
    function Get-Message {
        InModuleScope BATCRelayBot -Parameters @{ I = $Install; C = $Config; L = $Log } {
            param($I, $C, $L)
            $lines = Show-PostInstallationMessage -InstallPath $I -ConfigPath $C -LogPath $L 6>&1
            ($lines | ForEach-Object { "$_" }) -join "`n"
        }
    }

    # Not a hand-kept list: a command added later has to be mentioned too.
    $Commands = (Import-PowerShellDataFile (Join-Path $ModuleRoot 'BATCRelayBot.psd1')).FunctionsToExport |
                Where-Object { $_ -ne 'Install-BATCRelayBot' }
}

Describe "Show-PostInstallationMessage" {

    It "writes nothing to the success stream" {
        InModuleScope BATCRelayBot -Parameters @{ I = $Install; C = $Config; L = $Log } {
            param($I, $C, $L)
            @(Show-PostInstallationMessage -InstallPath $I -ConfigPath $C -LogPath $L 6>$null).Count |
                Should -Be 0
        }
    }

    It "announces success exactly once" {
        ([regex]::Matches((Get-Message), '(?i)successful')).Count | Should -Be 1
    }

    It "says each fact once - no line repeats" {
        $lines = (Get-Message) -split "`n" |
                 ForEach-Object { $_.Trim() } |
                 Where-Object { $_ }

        $repeated = $lines | Group-Object | Where-Object { $_.Count -gt 1 }
        $repeated.Name | Should -BeNullOrEmpty
    }

    It "shows each path once" {
        $message = Get-Message
        foreach ($path in $Install, $Config, $Log) {
            ([regex]::Matches($message, [regex]::Escape($path))).Count |
                Should -Be 1 -Because "$path should appear once"
        }
    }

    It "names every command the user now has" {
        $message = Get-Message
        foreach ($command in $Commands) {
            $message | Should -Match ([regex]::Escape($command))
        }
    }

    It "points at the troubleshooting guide instead of reciting it" {
        $message = Get-Message
        $message | Should -Match 'TROUBLESHOOTING\.md'

        # The four "Problem: / Solution:" recipes that used to live here went
        # stale the moment the documentation moved on without them.
        $message | Should -Not -Match 'Problem:'
    }

    It "tells the user how to check the bot actually answers" {
        (Get-Message) | Should -Match '!batchelp'
    }
}
