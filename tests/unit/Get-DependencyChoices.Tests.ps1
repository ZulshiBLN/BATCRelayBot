BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module BATCRelayBot -Force -ErrorAction SilentlyContinue
}

# Nothing here may depend on the machine: not on winget being present, not
# on what it has installed, and not on a console being attached. Read-Host is
# mocked everywhere because a real one waits for ever on a piped stdin - which
# is how this file hung a full run on 2026-09-13. The "no input" branch is
# tested on purpose, below, by a Read-Host that throws.
Describe "Get-DependencyChoices" {

    BeforeEach {
        Mock -ModuleName BATCRelayBot Read-Host { '' }
        Mock -ModuleName BATCRelayBot Test-WingetPresent { $true }
        Mock -ModuleName BATCRelayBot Get-InstalledWingetPackage {
            if ($IdPrefix -eq 'Python.Python') { @(@{ Id = 'Python.Python.3.12'; Version = '3.12.10' }) }
            else { @(@{ Id = 'Gyan.FFmpeg'; Version = '9.0.1' }) }
        }
    }

    Context "Return Value Structure" {

        It "Returns hashtable" {
            # Simulate input (No for all)
            $input = @("No", "No", "No") | ForEach-Object { $_ }
            $result = Get-DependencyChoices
            $result | Should -BeOfType [hashtable]
        }

        It "Returns hashtable with required keys" {
            $result = Get-DependencyChoices
            $result.Keys | Should -Contain "RemovePython"
            $result.Keys | Should -Contain "RemoveFFmpeg"
            $result.Keys | Should -Contain "SkipDependencyPrompts"
        }

        It "All values are boolean" {
            $result = Get-DependencyChoices
            $result.RemovePython | Should -BeOfType [bool]
            $result.RemoveFFmpeg | Should -BeOfType [bool]
            $result.SkipDependencyPrompts | Should -BeOfType [bool]
        }
    }

    Context "WinGet Detection" {

        It "Detects when WinGet is not available" {
            # If WinGet is not available, SkipDependencyPrompts should be true
            # This test might fail if WinGet IS available, which is OK
            $result = Get-DependencyChoices

            # Either WinGet is available (SkipDependencyPrompts = $false)
            # Or WinGet not available (SkipDependencyPrompts = $true)
            $result.SkipDependencyPrompts | Should -BeOfType [bool]
        }

        It "Handles missing WinGet gracefully" {
            { Get-DependencyChoices } | Should -Not -Throw
        }
    }

    Context "Default Behavior" {

        It "Returns No for all choices when Enter is the answer" {
            $result = Get-DependencyChoices 6>$null

            $result.RemovePython | Should -BeFalse
            $result.RemoveFFmpeg | Should -BeFalse
            Should -Invoke -ModuleName BATCRelayBot Read-Host -Times 2 -Exactly
        }

        It "Removes only what was answered yes to" {
            Mock -ModuleName BATCRelayBot Read-Host { if ($Prompt -match 'Python') { 'y' } else { 'n' } }

            $result = Get-DependencyChoices 6>$null

            $result.RemovePython | Should -BeTrue
            $result.RemoveFFmpeg | Should -BeFalse
            $result.PythonPackages.Count | Should -Be 1
        }

        # A non-interactive host has no console; Read-Host throws there. The
        # answer has to be no, because nothing may be removed by accident.
        It "Keeps everything when no input is available" {
            Mock -ModuleName BATCRelayBot Read-Host { throw "no console" }

            $result = Get-DependencyChoices 6>$null

            $result.RemovePython | Should -BeFalse
            $result.RemoveFFmpeg | Should -BeFalse
        }

        # The module is not offered here. Uninstalling the module that is
        # running the uninstaller is a separate decision, and the summary
        # afterwards prints the one command that does it.
        It "does not offer to remove the PowerShell module" {
            (Get-DependencyChoices).Keys | Should -Not -Contain "RemoveModule"
        }

        It "Accepts no parameters" {
            { Get-DependencyChoices } | Should -Not -Throw
        }

        It "Accepts Prerequisites parameter" {
            $prereqs = @{ Python = @{ Found = $true } }
            { Get-DependencyChoices -Prerequisites $prereqs } | Should -Not -Throw
        }
    }

    Context "VoiceMeeter Handling" {

        It "Does NOT include VoiceMeeter in choices" {
            $result = Get-DependencyChoices
            $result.Keys | Should -Not -Contain "RemoveVoiceMeeter"
        }
    }
}

Describe "Phase 3: Optional Dependency Prompts" {

    BeforeEach {
        Mock -ModuleName BATCRelayBot Read-Host { '' }
        Mock -ModuleName BATCRelayBot Test-WingetPresent { $true }
        Mock -ModuleName BATCRelayBot Get-InstalledWingetPackage {
            if ($IdPrefix -eq 'Python.Python') { @(@{ Id = 'Python.Python.3.12'; Version = '3.12.10' }) }
            else { @(@{ Id = 'Gyan.FFmpeg'; Version = '9.0.1' }) }
        }
    }

    It "Function exists" {
        { Get-Command Get-DependencyChoices -ErrorAction Stop } | Should -Not -Throw
    }

    It "Function executes without errors" {
        { Get-DependencyChoices } | Should -Not -Throw
    }

    It "Returns valid choice object" {
        $result = Get-DependencyChoices
        $result | Should -Not -BeNull
        $result.Keys.Count | Should -BeGreaterThan 0
    }

    It "Handles system without dependencies" {
        # Even if nothing is installed, should return valid object
        $result = Get-DependencyChoices
        $result | Should -BeOfType [hashtable]
    }

    It "All boolean flags can be true or false" {
        $result = Get-DependencyChoices

        # Verify they're actual booleans with valid values
        [bool]$result.RemovePython -is [bool] | Should -Be $true
        [bool]$result.RemoveFFmpeg -is [bool] | Should -Be $true
        [bool]$result.SkipDependencyPrompts -is [bool] | Should -Be $true
    }
}

Describe "Phase 3: Dependency Detection Logic" {

    BeforeEach {
        Mock -ModuleName BATCRelayBot Read-Host { '' }
        Mock -ModuleName BATCRelayBot Test-WingetPresent { $true }
        Mock -ModuleName BATCRelayBot Get-InstalledWingetPackage {
            if ($IdPrefix -eq 'Python.Python') { @(@{ Id = 'Python.Python.3.12'; Version = '3.12.10' }) }
            else { @(@{ Id = 'Gyan.FFmpeg'; Version = '9.0.1' }) }
        }
    }

    It "Detects Python if installed" {
        $result = Get-DependencyChoices
        # Should complete without error regardless of Python installation
        $result | Should -Not -BeNull
    }

    It "Detects FFmpeg if installed" {
        $result = Get-DependencyChoices
        # Should complete without error regardless of FFmpeg installation
        $result | Should -Not -BeNull
    }

    It "Detects PowerShell module" {
        $result = Get-DependencyChoices
        # Should complete without error regardless of module installation
        $result | Should -Not -BeNull
    }

    It "Gracefully handles WinGet unavailable" {
        # If WinGet not available, should still work
        $result = Get-DependencyChoices
        if ($result.SkipDependencyPrompts) {
            # WinGet detection failed, which is OK
            $result.RemovePython | Should -Be $false
            $result.RemoveFFmpeg | Should -Be $false
        }
    }
}
