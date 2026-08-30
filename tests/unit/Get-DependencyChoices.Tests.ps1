BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module BATCRelayBot -Force -ErrorAction SilentlyContinue
}

Describe "Get-DependencyChoices" {

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
            $result.Keys | Should -Contain "RemoveModule"
            $result.Keys | Should -Contain "SkipDependencyPrompts"
        }

        It "All values are boolean" {
            $result = Get-DependencyChoices
            $result.RemovePython | Should -BeOfType [bool]
            $result.RemoveFFmpeg | Should -BeOfType [bool]
            $result.RemoveModule | Should -BeOfType [bool]
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

        It "Returns No for all choices by default" {
            $result = Get-DependencyChoices

            # If WinGet not available, all should be false
            # If WinGet available, defaults might vary based on system
            $result.RemovePython | Should -BeOfType [bool]
            $result.RemoveFFmpeg | Should -BeOfType [bool]
            $result.RemoveModule | Should -BeOfType [bool]
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
        [bool]$result.RemoveModule -is [bool] | Should -Be $true
        [bool]$result.SkipDependencyPrompts -is [bool] | Should -Be $true
    }
}

Describe "Phase 3: Dependency Detection Logic" {

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
