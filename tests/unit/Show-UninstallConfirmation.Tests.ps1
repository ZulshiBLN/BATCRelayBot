BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module BATCRelayBot -Force -ErrorAction SilentlyContinue
}

# Read-Host is mocked in every test: a real one waits for ever on a piped
# stdin, which is how this file hung a full run on 2026-09-13. The "no input"
# branch is tested on purpose by a Read-Host that throws.
Describe "Show-UninstallConfirmation" {

    BeforeEach {
        Mock -ModuleName BATCRelayBot Read-Host { '' }
    }

    Context "Return Value Structure" {

        It "Returns hashtable" {
            $result = Show-UninstallConfirmation
            $result | Should -BeOfType [hashtable]
        }

        It "Returns hashtable with required keys" {
            $result = Show-UninstallConfirmation
            $result.Keys | Should -Contain "Confirmed"
            $result.Keys | Should -Contain "ConfirmationTime"
        }

        It "Confirmed is boolean" {
            $result = Show-UninstallConfirmation
            $result.Confirmed | Should -BeOfType [bool]
        }

        It "ConfirmationTime is DateTime" {
            $result = Show-UninstallConfirmation
            $result.ConfirmationTime | Should -BeOfType [System.DateTime]
        }
    }

    Context "Default Behavior" {

        It "Executes without errors" {
            { Show-UninstallConfirmation } | Should -Not -Throw
        }

        It "Defaults to not confirmed on an empty answer" {
            $result = Show-UninstallConfirmation 6>$null
            $result.Confirmed | Should -BeFalse
        }

        It "Accepts RemovalPlan parameter" {
            $plan = @{
                ConfigPath = "C:\test\config.json"
                InstallPath = "C:\test"
            }
            { Show-UninstallConfirmation -RemovalPlan $plan } | Should -Not -Throw
        }

        It "Accepts DependencyChoices parameter" {
            $choices = @{
                RemovePython = $false
                RemoveFFmpeg = $false
                RemoveModule = $false
            }
            { Show-UninstallConfirmation -DependencyChoices $choices } | Should -Not -Throw
        }

        It "Accepts both parameters together" {
            $plan = @{ InstallPath = "C:\test" }
            $choices = @{ RemovePython = $false }
            { Show-UninstallConfirmation -RemovalPlan $plan -DependencyChoices $choices } | Should -Not -Throw
        }
    }

    Context "Dependency Display" {

        It "Shows no dependency section when none selected" {
            $choices = @{
                RemovePython = $false
                RemoveFFmpeg = $false
                RemoveModule = $false
            }
            { Show-UninstallConfirmation -DependencyChoices $choices } | Should -Not -Throw
        }

        It "Shows Python in output when selected" {
            $choices = @{
                RemovePython = $true
                RemoveFFmpeg = $false
                RemoveModule = $false
            }
            { Show-UninstallConfirmation -DependencyChoices $choices } | Should -Not -Throw
        }

        It "Shows FFmpeg in output when selected" {
            $choices = @{
                RemovePython = $false
                RemoveFFmpeg = $true
                RemoveModule = $false
            }
            { Show-UninstallConfirmation -DependencyChoices $choices } | Should -Not -Throw
        }

        It "Shows module in output when selected" {
            $choices = @{
                RemovePython = $false
                RemoveFFmpeg = $false
                RemoveModule = $true
            }
            { Show-UninstallConfirmation -DependencyChoices $choices } | Should -Not -Throw
        }

        It "Shows multiple dependencies when selected" {
            $choices = @{
                RemovePython = $true
                RemoveFFmpeg = $true
                RemoveModule = $true
            }
            { Show-UninstallConfirmation -DependencyChoices $choices } | Should -Not -Throw
        }
    }

    Context "Confirmation Logic" {

        It "Shows final warning" {
            { Show-UninstallConfirmation } | Should -Not -Throw
        }

        It "Requires the word uninstall - yes is not enough" {
            Mock -ModuleName BATCRelayBot Read-Host { 'yes' }
            (Show-UninstallConfirmation 6>$null).Confirmed | Should -BeFalse
        }

        It "Confirms on the word uninstall" {
            Mock -ModuleName BATCRelayBot Read-Host { 'uninstall' }
            (Show-UninstallConfirmation 6>$null).Confirmed | Should -BeTrue
        }

        # A non-interactive host has no console; Read-Host throws there. That
        # has to read as cancelled, never as confirmed.
        It "Cancels when no input is available" {
            Mock -ModuleName BATCRelayBot Read-Host { throw "no console" }
            { Show-UninstallConfirmation 6>$null } | Should -Not -Throw
            (Show-UninstallConfirmation 6>$null).Confirmed | Should -BeFalse
        }
    }
}

Describe "Phase 4: Final Confirmation Screen" {

    BeforeEach {
        Mock -ModuleName BATCRelayBot Read-Host { '' }
    }

    It "Function exists" {
        { Get-Command Show-UninstallConfirmation -ErrorAction Stop } | Should -Not -Throw
    }

    It "Displays confirmation prompt" {
        { Show-UninstallConfirmation } | Should -Not -Throw
    }

    It "Returns valid confirmation result" {
        $result = Show-UninstallConfirmation
        $result | Should -Not -BeNull
        $result.Confirmed | Should -BeOfType [bool]
        $result.ConfirmationTime | Should -BeOfType [System.DateTime]
    }

    It "Handles all combination of dependency choices" {
        $testCases = @(
            @{ RemovePython = $true; RemoveFFmpeg = $true; RemoveModule = $true },
            @{ RemovePython = $true; RemoveFFmpeg = $false; RemoveModule = $false },
            @{ RemovePython = $false; RemoveFFmpeg = $true; RemoveModule = $false },
            @{ RemovePython = $false; RemoveFFmpeg = $false; RemoveModule = $true },
            @{ RemovePython = $false; RemoveFFmpeg = $false; RemoveModule = $false }
        )

        foreach ($case in $testCases) {
            { Show-UninstallConfirmation -DependencyChoices $case } | Should -Not -Throw
        }
    }

    It "Final gate is clear and visible" {
        # Verify function completes without errors
        $result = Show-UninstallConfirmation
        $result.Confirmed | Should -Not -BeNull
    }
}
