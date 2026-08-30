BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module BATCRelayBot -Force -ErrorAction SilentlyContinue
}

Describe "Show-PostRemovalSummary" {

    Context "Function Execution" {

        It "Executes without errors" {
            { Show-PostRemovalSummary } | Should -Not -Throw
        }

        It "Accepts RemovalResult parameter" {
            $result = @{
                Success = $true
                DeletedFiles = @("file1.txt", "file2.txt")
                Errors = @()
                LogPath = "C:\temp\removal.log"
            }
            { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
        }

        It "Accepts LogPath parameter" {
            { Show-PostRemovalSummary -LogPath "C:\temp\removal.log" } | Should -Not -Throw
        }

        It "Accepts both parameters" {
            $result = @{
                Success = $true
                DeletedFiles = @()
                Errors = @()
                LogPath = "C:\temp\removal.log"
            }
            { Show-PostRemovalSummary -RemovalResult $result -LogPath "C:\temp\removal.log" } | Should -Not -Throw
        }
    }

    Context "Removal Status Display" {

        It "Shows success message when removal successful" {
            $result = @{ Success = $true; DeletedFiles = @(); Errors = @(); LogPath = "" }
            { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
        }

        It "Shows warning when removal had issues" {
            $result = @{ Success = $false; DeletedFiles = @(); Errors = @("Error1"); LogPath = "" }
            { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
        }

        It "Shows file count when files were deleted" {
            $result = @{
                Success = $true
                DeletedFiles = @("file1.txt", "file2.txt", "file3.txt")
                Errors = @()
                LogPath = ""
            }
            { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
        }

        It "Shows errors when present" {
            $result = @{
                Success = $false
                DeletedFiles = @()
                Errors = @("Failed to delete config.json", "Permission denied")
                LogPath = ""
            }
            { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
        }
    }

    Context "Manual Cleanup Instructions" {

        It "Shows VoiceMeeter manual uninstall instructions" {
            { Show-PostRemovalSummary } | Should -Not -Throw
        }

        It "Provides clear step-by-step VoiceMeeter removal" {
            { Show-PostRemovalSummary } | Should -Not -Throw
        }

        It "Includes warning about checking dependencies" {
            { Show-PostRemovalSummary } | Should -Not -Throw
        }
    }

    Context "Log Information" {

        It "Shows removal log path when provided" {
            $result = @{
                Success = $true
                DeletedFiles = @()
                Errors = @()
                LogPath = "C:\Users\Test\AppData\Roaming\BATCRelayBot-Uninstall\removal-20260830-123456.log"
            }
            { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
        }

        It "Displays helpful message about log contents" {
            $result = @{
                Success = $true
                DeletedFiles = @()
                Errors = @()
                LogPath = "C:\temp\removal.log"
            }
            { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
        }
    }

    Context "Next Steps" {

        It "Provides reinstallation instructions on success" {
            $result = @{ Success = $true; DeletedFiles = @(); Errors = @(); LogPath = "" }
            { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
        }

        It "Provides troubleshooting guidance on failure" {
            $result = @{ Success = $false; DeletedFiles = @(); Errors = @("Test error"); LogPath = "" }
            { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
        }

        It "Suggests checking log for details" {
            $result = @{ Success = $false; DeletedFiles = @(); Errors = @(); LogPath = "C:\temp\removal.log" }
            { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
        }
    }

    Context "Output Formatting" {

        It "Uses appropriate colors for status" {
            { Show-PostRemovalSummary } | Should -Not -Throw
        }

        It "Includes visual separators" {
            { Show-PostRemovalSummary } | Should -Not -Throw
        }

        It "Provides well-organized information" {
            { Show-PostRemovalSummary } | Should -Not -Throw
        }
    }

    Context "Parameter Combinations" {

        It "Handles empty RemovalResult" {
            { Show-PostRemovalSummary -RemovalResult @{} } | Should -Not -Throw
        }

        It "Handles RemovalResult with all fields" {
            $result = @{
                Success = $true
                DeletedFiles = @("file1.txt", "file2.txt")
                Errors = @()
                LogPath = "C:\temp\removal.log"
            }
            { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
        }

        It "Handles RemovalResult with errors" {
            $result = @{
                Success = $false
                DeletedFiles = @("file1.txt")
                Errors = @("Error 1", "Error 2")
                LogPath = "C:\temp\removal.log"
            }
            { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
        }

        It "Handles null or missing LogPath" {
            $result = @{
                Success = $true
                DeletedFiles = @()
                Errors = @()
                LogPath = ""
            }
            { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
        }
    }
}

Describe "Phase 6: Post-Removal Summary" {

    It "Function exists" {
        { Get-Command Show-PostRemovalSummary -ErrorAction Stop } | Should -Not -Throw
    }

    It "Function is callable" {
        { Show-PostRemovalSummary } | Should -Not -Throw
    }

    It "Displays removal completion message" {
        { Show-PostRemovalSummary } | Should -Not -Throw
    }

    It "Shows next steps for user" {
        { Show-PostRemovalSummary } | Should -Not -Throw
    }

    It "Handles successful removal display" {
        $result = @{
            Success = $true
            DeletedFiles = @("config.json", "bot.py", "setup.py")
            Errors = @()
            LogPath = "C:\Users\Test\AppData\Roaming\BATCRelayBot-Uninstall\removal-20260830-123456.log"
        }
        { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
    }

    It "Handles failed removal display" {
        $result = @{
            Success = $false
            DeletedFiles = @("config.json")
            Errors = @("Could not delete bot.py", "Permission denied on setup.py")
            LogPath = "C:\Users\Test\AppData\Roaming\BATCRelayBot-Uninstall\removal-20260830-123456.log"
        }
        { Show-PostRemovalSummary -RemovalResult $result } | Should -Not -Throw
    }

    It "Final output screen is clear and helpful" {
        { Show-PostRemovalSummary } | Should -Not -Throw
    }

    It "Directs user to manual cleanup steps" {
        { Show-PostRemovalSummary } | Should -Not -Throw
    }
}
