# Setup refuses to run from a stale module (1.6.2).
#
# Update-Module installs the new version beside the old while the PowerShell
# window keeps running the one it loaded. Install-BATCRelayBot typed in that
# window runs the old setup and copies the old bot.py. On 2026-09-12 that
# failed because the old folder was gone; on 2026-09-13 it "succeeded" and
# installed 1.6.0 under a 1.6.1 banner. Setup now compares its own version
# with the newest on disk before it touches anything.

BeforeAll {
    Import-Module "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1" -Force

    function New-ModuleInfo {
        param([string]$Version)
        [pscustomobject]@{ Name = 'BATCRelayBot'; Version = [version]$Version }
    }
}

Describe "Test-ModuleIsCurrent" {

    BeforeEach {
        Mock -ModuleName BATCRelayBot Write-InstallLog { }
        Mock -ModuleName BATCRelayBot Get-ModuleVersion { '1.6.1' }
    }

    It "is current when the running version is the newest on disk" {
        Mock -ModuleName BATCRelayBot Get-Module { @((New-ModuleInfo '1.6.0'), (New-ModuleInfo '1.6.1')) }

        $result = Test-ModuleIsCurrent
        $result.Current | Should -BeTrue
        $result.Running | Should -Be ([version]'1.6.1')
        $result.Newest | Should -Be ([version]'1.6.1')
    }

    It "is stale when a newer version is installed than the one running" {
        Mock -ModuleName BATCRelayBot Get-Module { @((New-ModuleInfo '1.6.1'), (New-ModuleInfo '1.6.2')) }

        $result = Test-ModuleIsCurrent
        $result.Current | Should -BeFalse
        $result.Running | Should -Be ([version]'1.6.1')
        $result.Newest | Should -Be ([version]'1.6.2')
    }

    It "is current when the running copy is not installed at all, as in a checkout" {
        Mock -ModuleName BATCRelayBot Get-Module { @() }

        (Test-ModuleIsCurrent).Current | Should -BeTrue
    }

    It "is current when the running copy is newer than anything installed" {
        Mock -ModuleName BATCRelayBot Get-ModuleVersion { '1.7.0' }
        Mock -ModuleName BATCRelayBot Get-Module { @(New-ModuleInfo '1.6.2') }

        (Test-ModuleIsCurrent).Current | Should -BeTrue
    }

    # Michel's decision: the check is a help, not a bar. A setup that fails
    # on its own help would be worse than the mistake it guards against.
    It "carries on with a warning when the comparison itself fails" {
        Mock -ModuleName BATCRelayBot Get-Module { throw "module path unavailable" }

        $result = Test-ModuleIsCurrent -LogPath 'x'
        $result.Current | Should -BeTrue
        $result.Warning | Should -Match 'module path unavailable'
        Should -Invoke -ModuleName BATCRelayBot Write-InstallLog -Times 1 -Exactly `
            -ParameterFilter { $Level -eq 'WARN' }
    }

    It "carries on with a warning when its own version is unknown" {
        Mock -ModuleName BATCRelayBot Get-ModuleVersion { 'unknown' }
        Mock -ModuleName BATCRelayBot Get-Module { @(New-ModuleInfo '1.6.2') }

        $result = Test-ModuleIsCurrent
        $result.Current | Should -BeTrue
        $result.Warning | Should -Not -BeNullOrEmpty
    }
}

Describe "Install-BATCRelayBot and a stale module" {

    It "stops before phase 0, names both versions and says to open a new window" {
        Mock -ModuleName BATCRelayBot Test-ModuleIsCurrent {
            @{ Current = $false; Running = [version]'1.6.1'; Newest = [version]'1.6.2' }
        }
        Mock -ModuleName BATCRelayBot Convert-LegacyBotConfig { throw "phase 0 must not run" }
        Mock -ModuleName BATCRelayBot Find-Python { throw "phase 1 must not run" }
        Mock -ModuleName BATCRelayBot Read-Host { '' }

        $sandbox = Join-Path $env:TEMP ("stale-" + [guid]::NewGuid().ToString('N'))
        try {
            $screen = Install-BATCRelayBot -BotPath $sandbox -PassThru 6>&1
            $result = $screen | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1
            $text = ($screen | Where-Object { $_ -is [System.Management.Automation.InformationRecord] }) | Out-String

            $result.Success | Should -BeFalse
            $result.Error | Should -Match 'newer version'
            $text | Should -Match '1\.6\.1'
            $text | Should -Match '1\.6\.2'
            $text | Should -Match 'new (PowerShell )?window'
            Should -Invoke -ModuleName BATCRelayBot Convert-LegacyBotConfig -Times 0
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "runs on when the module is current" {
        Mock -ModuleName BATCRelayBot Test-ModuleIsCurrent {
            @{ Current = $true; Running = [version]'1.6.2'; Newest = [version]'1.6.2' }
        }
        # Phase 1 is the first thing after the check; reaching it is enough to
        # show the check let the run through. The installer catches the throw
        # itself and reports it, so the call is counted rather than caught.
        Mock -ModuleName BATCRelayBot Find-Python { throw "reached phase 1" }
        Mock -ModuleName BATCRelayBot Read-Host { '' }

        $sandbox = Join-Path $env:TEMP ("current-" + [guid]::NewGuid().ToString('N'))
        try {
            Install-BATCRelayBot -BotPath $sandbox -PassThru 6>$null | Out-Null
            Should -Invoke -ModuleName BATCRelayBot Find-Python -Times 1 -Exactly
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
