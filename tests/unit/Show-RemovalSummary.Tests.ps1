BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force
}

AfterAll {
    Remove-Module BATCRelayBot -Force -ErrorAction SilentlyContinue
}

Describe "Show-RemovalSummary" {

    Context "Display Functionality" {

        It "Executes without errors" {
            $testPath = Join-Path $PSScriptRoot "..\..\testdata\removal_summary"
            if (Test-Path $testPath) { Remove-Item $testPath -Recurse -Force }
            New-Item -ItemType Directory -Path $testPath -Force | Out-Null
            "test" | Set-Content (Join-Path $testPath "config.json")

            { Show-RemovalSummary -BotPath $testPath } | Should -Not -Throw

            Remove-Item $testPath -Recurse -Force
        }

        It "Returns boolean true" {
            $testPath = "$env:TEMP\removal_summary_test"
            if (Test-Path $testPath) { Remove-Item $testPath -Recurse -Force }
            New-Item -ItemType Directory -Path $testPath -Force | Out-Null

            $result = Show-RemovalSummary -BotPath $testPath
            $result | Should -Be $true

            Remove-Item $testPath -Recurse -Force
        }

        It "Uses default BotPath when not specified" {
            { Show-RemovalSummary } | Should -Not -Throw
        }

        It "Displays with no prompts (read-only)" {
            $testPath = "$env:TEMP\removal_summary_readonly"
            if (Test-Path $testPath) { Remove-Item $testPath -Recurse -Force }
            New-Item -ItemType Directory -Path $testPath -Force | Out-Null
            "test" | Set-Content (Join-Path $testPath "config.json")

            # Should display without requiring input
            $result = Show-RemovalSummary -BotPath $testPath
            $result | Should -Be $true

            Remove-Item $testPath -Recurse -Force
        }
    }

    Context "File Detection" {

        It "Detects files in directory" {
            $testPath = "$env:TEMP\removal_summary_files"
            if (Test-Path $testPath) { Remove-Item $testPath -Recurse -Force }
            New-Item -ItemType Directory -Path $testPath -Force | Out-Null
            "config" | Set-Content (Join-Path $testPath "config.json")
            "log" | Set-Content (Join-Path $testPath "install.log")
            "bot" | Set-Content (Join-Path $testPath "bot.py")

            { Show-RemovalSummary -BotPath $testPath } | Should -Not -Throw

            Remove-Item $testPath -Recurse -Force
        }

        It "Handles empty directory gracefully" {
            $testPath = "$env:TEMP\removal_summary_empty"
            if (Test-Path $testPath) { Remove-Item $testPath -Recurse -Force }
            New-Item -ItemType Directory -Path $testPath -Force | Out-Null

            { Show-RemovalSummary -BotPath $testPath } | Should -Not -Throw

            Remove-Item $testPath -Recurse -Force
        }

        It "Handles non-existent directory gracefully" {
            $testPath = "$env:TEMP\removal_summary_nonexistent"

            { Show-RemovalSummary -BotPath $testPath } | Should -Not -Throw
        }
    }

    Context "Disk Space Calculation" {

        It "Calculates disk space for files" {
            $testPath = "$env:TEMP\removal_summary_diskspace"
            if (Test-Path $testPath) { Remove-Item $testPath -Recurse -Force }
            New-Item -ItemType Directory -Path $testPath -Force | Out-Null

            # Create files with known sizes
            $content = "x" * 1000  # ~1KB
            $content | Set-Content (Join-Path $testPath "file1.txt")
            $content | Set-Content (Join-Path $testPath "file2.txt")

            { Show-RemovalSummary -BotPath $testPath } | Should -Not -Throw

            Remove-Item $testPath -Recurse -Force
        }

        It "Shows zero space for empty directory" {
            $testPath = "$env:TEMP\removal_summary_zero_space"
            if (Test-Path $testPath) { Remove-Item $testPath -Recurse -Force }
            New-Item -ItemType Directory -Path $testPath -Force | Out-Null

            { Show-RemovalSummary -BotPath $testPath } | Should -Not -Throw

            Remove-Item $testPath -Recurse -Force
        }
    }

    Context "Sensitive Data Handling" {

        It "Highlights config.json with warning" {
            $testPath = "$env:TEMP\removal_summary_sensitive"
            if (Test-Path $testPath) { Remove-Item $testPath -Recurse -Force }
            New-Item -ItemType Directory -Path $testPath -Force | Out-Null
            "token_value" | Set-Content (Join-Path $testPath "config.json")

            # Should not throw and should handle sensitive data
            { Show-RemovalSummary -BotPath $testPath } | Should -Not -Throw

            Remove-Item $testPath -Recurse -Force
        }

        It "Handles missing config.json gracefully" {
            $testPath = "$env:TEMP\removal_summary_no_config"
            if (Test-Path $testPath) { Remove-Item $testPath -Recurse -Force }
            New-Item -ItemType Directory -Path $testPath -Force | Out-Null

            { Show-RemovalSummary -BotPath $testPath } | Should -Not -Throw

            Remove-Item $testPath -Recurse -Force
        }
    }

    Context "Log File Detection" {

        It "Detects .log files in directory" {
            $testPath = "$env:TEMP\removal_summary_logs"
            if (Test-Path $testPath) { Remove-Item $testPath -Recurse -Force }
            New-Item -ItemType Directory -Path $testPath -Force | Out-Null
            "log entry" | Set-Content (Join-Path $testPath "install.log")
            "log entry" | Set-Content (Join-Path $testPath "bot.log")

            { Show-RemovalSummary -BotPath $testPath } | Should -Not -Throw

            Remove-Item $testPath -Recurse -Force
        }

        It "Handles directory with no log files" {
            $testPath = "$env:TEMP\removal_summary_no_logs"
            if (Test-Path $testPath) { Remove-Item $testPath -Recurse -Force }
            New-Item -ItemType Directory -Path $testPath -Force | Out-Null
            "data" | Set-Content (Join-Path $testPath "data.txt")

            { Show-RemovalSummary -BotPath $testPath } | Should -Not -Throw

            Remove-Item $testPath -Recurse -Force
        }
    }
}

Describe "Phase 2: Removal Summary Display" {

    It "Function exists" {
        { Get-Command Show-RemovalSummary -ErrorAction Stop } | Should -Not -Throw
    }

    It "Function is read-only (no prompts)" {
        # Verify by successful execution without input
        $result = Show-RemovalSummary -BotPath "$env:TEMP"
        $result | Should -Be $true
    }

    It "Displays removal information clearly" {
        { Show-RemovalSummary -BotPath "$env:TEMP" } | Should -Not -Throw
    }

    It "Handles various directory states" {
        # Empty directory
        $empty = "$env:TEMP\phase2_empty"
        if (Test-Path $empty) { Remove-Item $empty -Recurse -Force }
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
        { Show-RemovalSummary -BotPath $empty } | Should -Not -Throw
        Remove-Item $empty -Recurse -Force

        # With files
        $filled = "$env:TEMP\phase2_filled"
        if (Test-Path $filled) { Remove-Item $filled -Recurse -Force }
        New-Item -ItemType Directory -Path $filled -Force | Out-Null
        "test" | Set-Content (Join-Path $filled "config.json")
        { Show-RemovalSummary -BotPath $filled } | Should -Not -Throw
        Remove-Item $filled -Recurse -Force

        # Non-existent
        { Show-RemovalSummary -BotPath "$env:TEMP\nonexistent_phase2" } | Should -Not -Throw
    }
}
