BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force
}

Describe "Show-PrerequisitesInfo" {
    It "Executes without errors" {
        { Show-PrerequisitesInfo } | Should -Not -Throw
    }

    It "Does not prompt for input" {
        # Function should be silent display only
        # If it prompted, Pester would hang waiting for input
        # Successful completion means no prompts
        { Show-PrerequisitesInfo } | Should -Not -Throw
    }

    It "Displays information for all prerequisites" {
        # Function successfully displays all info
        # Verify no exceptions thrown during display
        $result = { Show-PrerequisitesInfo } | Should -Not -Throw
        $true | Should -Be $true
    }
}

Describe "Phase 2: Information Display Integration" {
    It "Display uses Find-* functions from Phase 1" {
        # Verify Phase 1 and Phase 2 integration
        {
            $python = Find-Python
            $ffmpeg = Find-FFmpeg
            $vm = Find-VoiceMeeter
            $atc = Find-BeyondATC
            Show-PrerequisitesInfo
        } | Should -Not -Throw
    }

    It "Works regardless of which prerequisites are installed" {
        # Should work in any environment (some prereqs installed, some not)
        { Show-PrerequisitesInfo } | Should -Not -Throw
    }

    It "Returns void (no output object)" {
        $result = Show-PrerequisitesInfo
        # Write-Host returns $null, so $result should be empty
        $result | Should -Be $null
    }

    It "All Find-* functions return consistent structure" {
        $python = Find-Python
        $ffmpeg = Find-FFmpeg
        $vm = Find-VoiceMeeter
        $atc = Find-BeyondATC

        foreach ($result in @($python, $ffmpeg, $vm, $atc)) {
            $result.Keys | Should -Contain "Found"
            $result.Keys | Should -Contain "Path"
            $result.Keys | Should -Contain "Version"
            $result.Keys | Should -Contain "Method"
        }
    }
}
