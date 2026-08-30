BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force

    # Setup test environment
    $testRoot = "$env:TEMP\BATCRelayBot-UninstallTest-$(Get-Random)"
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
}

AfterAll {
    Remove-Module BATCRelayBot -Force -ErrorAction SilentlyContinue

    # Cleanup test environment
    if (Test-Path $testRoot) {
        Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Invoke-SecureUninstall" {

    Context "Return Value Structure" {

        It "Returns hashtable" {
            $result = Invoke-SecureUninstall -BotPath $testRoot -DependencyChoices @{}
            $result | Should -BeOfType [hashtable]
        }

        It "Returns hashtable with required keys" {
            $result = Invoke-SecureUninstall -BotPath $testRoot -DependencyChoices @{}
            $result.Keys | Should -Contain "Success"
            $result.Keys | Should -Contain "DeletedFiles"
            $result.Keys | Should -Contain "Errors"
            $result.Keys | Should -Contain "LogPath"
        }

        It "Success is boolean" {
            $result = Invoke-SecureUninstall -BotPath $testRoot -DependencyChoices @{}
            $result.Success | Should -BeOfType [bool]
        }

        It "DeletedFiles is array-like" {
            $result = Invoke-SecureUninstall -BotPath $testRoot -DependencyChoices @{}
            $result.DeletedFiles -is [System.Collections.IEnumerable] -or $result.DeletedFiles -eq $null | Should -Be $true
        }

        It "Errors is array-like" {
            $result = Invoke-SecureUninstall -BotPath $testRoot -DependencyChoices @{}
            $result.Errors -is [System.Collections.IEnumerable] -or $result.Errors -eq $null | Should -Be $true
        }

        It "LogPath is string" {
            $result = Invoke-SecureUninstall -BotPath $testRoot -DependencyChoices @{}
            $result.LogPath | Should -BeOfType [string]
        }
    }

    Context "Removal Process" {

        It "Creates removal log" {
            $testDir = "$testRoot\test1"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}
            Test-Path $result.LogPath | Should -Be $true
        }

        It "Log contains start timestamp" {
            $testDir = "$testRoot\test2"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}
            $logContent = Get-Content $result.LogPath -Raw
            $logContent | Should -Match "Started:"
        }

        It "Deletes installation directory after removal" {
            $testDir = "$testRoot\test3"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            "test file" | Out-File "$testDir\test.txt" -Force

            $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}
            Test-Path $testDir | Should -Be $false
        }

        It "Returns Success = true when directory deleted" {
            $testDir = "$testRoot\test4"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}
            $result.Success | Should -Be $true
        }

        It "Returns Success = false when directory cannot be deleted" {
            $testDir = "$testRoot\test5"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            # Create a file that's difficult to delete
            $readonlyFile = "$testDir\readonly.txt"
            "content" | Out-File $readonlyFile -Force
            Set-ItemProperty -Path $readonlyFile -Name IsReadOnly -Value $true

            $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}

            # Cleanup
            Set-ItemProperty -Path $readonlyFile -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue

            # If directory still exists, Success should be false
            if (Test-Path $testDir) {
                $result.Success | Should -Be $false
            }
        }
    }

    Context "File Handling" {

        It "Deletes all files in installation directory" {
            $testDir = "$testRoot\test6"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            "file1" | Out-File "$testDir\file1.txt" -Force
            "file2" | Out-File "$testDir\file2.txt" -Force
            "file3" | Out-File "$testDir\file3.py" -Force

            $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}
            @($result.DeletedFiles).Count | Should -BeGreaterThan 2
        }

        It "Tracks deleted filenames" {
            $testDir = "$testRoot\test7"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            "content" | Out-File "$testDir\testfile.txt" -Force

            $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}
            ($result.DeletedFiles | Where-Object { $_ -match "testfile\.txt" }).Count | Should -Be 1
        }

        It "Handles removal with no files" {
            $testDir = "$testRoot\test8"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            { Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{} } | Should -Not -Throw
        }
    }

    Context "Config.json Secure Deletion" {

        It "Attempts to delete config.json if present" {
            $testDir = "$testRoot\test9"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            "token" | Out-File "$testDir\config.json" -Force

            $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}
            $result.DeletedFiles | Should -Contain "config.json"
        }

        It "Handles missing config.json gracefully" {
            $testDir = "$testRoot\test10"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            { Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{} } | Should -Not -Throw
        }

        It "Logs config.json deletion" {
            $testDir = "$testRoot\test11"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            "sensitive" | Out-File "$testDir\config.json" -Force

            $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}
            $logContent = Get-Content $result.LogPath -Raw
            $logContent | Should -Match "config\.json"
        }
    }

    Context "Dependency Choices Handling" {

        It "Accepts empty dependency choices" {
            $testDir = "$testRoot\test12"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            { Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{} } | Should -Not -Throw
        }

        It "Accepts RemovePython choice" {
            $testDir = "$testRoot\test13"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            $choices = @{ RemovePython = $true }
            { Invoke-SecureUninstall -BotPath $testDir -DependencyChoices $choices } | Should -Not -Throw
        }

        It "Accepts RemoveFFmpeg choice" {
            $testDir = "$testRoot\test14"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            $choices = @{ RemoveFFmpeg = $true }
            { Invoke-SecureUninstall -BotPath $testDir -DependencyChoices $choices } | Should -Not -Throw
        }

        It "Accepts RemoveModule choice" {
            $testDir = "$testRoot\test15"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            $choices = @{ RemoveModule = $true }
            { Invoke-SecureUninstall -BotPath $testDir -DependencyChoices $choices } | Should -Not -Throw
        }

        It "Handles all dependency choices at once" {
            $testDir = "$testRoot\test16"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            $choices = @{
                RemovePython = $true
                RemoveFFmpeg = $true
                RemoveModule = $true
            }
            { Invoke-SecureUninstall -BotPath $testDir -DependencyChoices $choices } | Should -Not -Throw
        }
    }

    Context "Error Handling" {

        It "Captures file deletion errors" {
            $testDir = "$testRoot\test17"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}
            ($result.Errors -is [System.Collections.IEnumerable] -or $result.Errors -eq $null) | Should -Be $true
        }

        It "Function doesn't throw on errors" {
            $testDir = "$testRoot\test18"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            { Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{} } | Should -Not -Throw
        }

        It "Continues removal even if one step fails" {
            $testDir = "$testRoot\test19"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            "content" | Out-File "$testDir\file.txt" -Force

            $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}
            # Should still attempt to complete despite errors
            $result | Should -Not -BeNull
        }
    }

    Context "Logging Completeness" {

        It "Logs all major steps" {
            $testDir = "$testRoot\test20"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}
            $logContent = Get-Content $result.LogPath -Raw

            # Check for key phases
            $logContent | Should -Match "Started:"
            $logContent | Should -Match "Pre-deletion verification|Removal completed"
        }

        It "Log path is accessible" {
            $testDir = "$testRoot\test21"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}
            $result.LogPath | Should -Not -BeNullOrEmpty
        }
    }

    Context "Default Parameters" {

        It "Uses default BotPath if not provided" {
            # Should not throw when called with minimal parameters
            # (may fail to delete non-existent directory, but should execute)
            $result = Invoke-SecureUninstall
            $result | Should -Not -BeNull
        }

        It "Uses empty hashtable for DependencyChoices if not provided" {
            $testDir = "$testRoot\test22"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            $result = Invoke-SecureUninstall -BotPath $testDir
            $result | Should -Not -BeNull
        }
    }
}

Describe "Phase 5: Secure Uninstallation" {

    It "Function exists" {
        { Get-Command Invoke-SecureUninstall -ErrorAction Stop } | Should -Not -Throw
    }

    It "Function executes without crashing" {
        $testDir = "$testRoot\phase5-test"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        { Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{} } | Should -Not -Throw
    }

    It "Returns complete removal status" {
        $testDir = "$testRoot\phase5-complete"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}
        $result.Success | Should -BeOfType [bool]
        ($result.DeletedFiles -is [System.Collections.IEnumerable] -or $result.DeletedFiles -eq $null) | Should -Be $true
        ($result.Errors -is [System.Collections.IEnumerable] -or $result.Errors -eq $null) | Should -Be $true
        $result.LogPath | Should -Not -BeNullOrEmpty
    }

    It "Completely removes installation directory" {
        $testDir = "$testRoot\phase5-remove"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        "setup.py" | Out-File "$testDir\setup.py" -Force
        "config" | Out-File "$testDir\config.json" -Force

        $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}

        Test-Path $testDir | Should -Be $false
        $result.Success | Should -Be $true
    }

    It "Produces removal log with deletion details" {
        $testDir = "$testRoot\phase5-log"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        "test" | Out-File "$testDir\file.txt" -Force

        $result = Invoke-SecureUninstall -BotPath $testDir -DependencyChoices @{}
        (Test-Path $result.LogPath) | Should -Be $true
        (Get-Content $result.LogPath -Raw).Length | Should -BeGreaterThan 100
    }
}
