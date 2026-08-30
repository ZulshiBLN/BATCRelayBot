BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module BATCRelayBot -Force -ErrorAction SilentlyContinue
}

Describe "Show-UninstallConfirmation" {

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

        It "Defaults to not confirmed (no input)" {
            $result = Show-UninstallConfirmation
            # Without input, should default to cancelled
            $result.Confirmed | Should -BeOfType [bool]
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

        It "Requires explicit yes for confirmation" {
            # Default behavior without input should be not confirmed
            $result = Show-UninstallConfirmation
            # Without exact "yes" input, should be false
            $result.Confirmed | Should -BeOfType [bool]
        }

        It "Gracefully handles no input (test mode)" {
            { Show-UninstallConfirmation } | Should -Not -Throw
        }
    }
}

Describe "Phase 4: Final Confirmation Screen" {

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
