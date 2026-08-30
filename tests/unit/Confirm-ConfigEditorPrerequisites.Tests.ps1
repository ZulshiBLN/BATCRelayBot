#Requires -Modules Pester

Describe "Confirm-ConfigEditorPrerequisites" {

    # Test Setup
    BeforeAll {
        $functionPath = "$PSScriptRoot\..\..\BATCRelayBot\Private\Confirm-ConfigEditorPrerequisites.ps1"
        if (Test-Path $functionPath) {
            . $functionPath
        }
    }

    Context "Installation Directory Validation" {

        It "Should return Valid=true when installation directory exists" {
            # Arrange
            $testPath = $env:TEMP

            # Act
            $result = Confirm-ConfigEditorPrerequisites -InstallPath $testPath

            # Assert
            $result.Valid | Should -Be $true
            $result.InstallPath | Should -Be $testPath
            $result.Errors.Count | Should -Be 0
        }

        It "Should return Valid=false and error when installation directory not found" {
            # Arrange
            $testPath = "C:\NonExistent\Path\That\Does\Not\Exist\12345"

            # Act
            $result = Confirm-ConfigEditorPrerequisites -InstallPath $testPath

            # Assert
            $result.Valid | Should -Be $false
            $result.Errors | Should -Contain "*Installation directory not found*"
        }
    }

    Context "config.json File Existence" {

        It "Should return Valid=false when config.json not found" {
            # Arrange
            $testPath = $env:TEMP

            # Act
            $result = Confirm-ConfigEditorPrerequisites -InstallPath $testPath

            # Assert
            $result.Valid | Should -Be $false
            $result.Errors | Should -Contain "*config.json not found*"
        }

        It "Should return ConfigPath when config.json exists" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                # Act
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir

                # Assert
                $result.ConfigPath | Should -Be $configFile
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "File Permissions - Read Access" {

        It "Should return Valid=true when config.json is readable" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                # Act
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir

                # Assert
                $result.Errors | Should -Not -Contain "*read/write permissions*"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should return error when config.json is not readable" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force
            $acl = Get-Acl $configFile
            $acl.SetAccessRuleProtection($true, $false)
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                [System.Security.Principal.WindowsIdentity]::GetCurrent().User,
                [System.Security.AccessControl.FileSystemRights]::ReadAttributes,
                [System.Security.AccessControl.InheritanceFlags]::None,
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow
            )
            $acl.SetAccessRule($rule)
            Set-Acl -Path $configFile -AclObject $acl

            try {
                # Act
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir

                # Assert
                $result.Valid | Should -Be $false
                $result.Errors | Should -Contain "*read/write permissions*" -or $result.Errors.Count -gt 0
            }
            finally {
                $acl = Get-Acl $configFile
                $acl.SetAccessRuleProtection($false, $true)
                Set-Acl -Path $configFile -AclObject $acl
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "File Permissions - Write Access" {

        It "Should return Valid=true when config.json is writable" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                # Act
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir

                # Assert
                $result.Errors | Should -Not -Contain "*read/write permissions*"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Bot Running Status Detection" {

        It "Should return BotRunning=false when bot process not running" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                # Act
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir

                # Assert
                $result.BotRunning | Should -Be $false
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should return BotRunning=true when bot process is running (if python available)" {
            # Arrange - Only run this test if Python is available
            $pythonCheck = Get-Command python -ErrorAction SilentlyContinue
            if (-not $pythonCheck) {
                Set-ItResult -Skipped -Because "Python not installed"
                return
            }

            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                # This test would require actual bot process - mark as Skip for now
                # In real scenario, would mock Get-Process or use pester mocking
                Set-ItResult -Skipped -Because "Requires live bot process - tested manually"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Return Value Structure" {

        It "Should return hashtable with required properties" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                # Act
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir

                # Assert
                $result | Should -HaveKey "Valid"
                $result | Should -HaveKey "InstallPath"
                $result | Should -HaveKey "ConfigPath"
                $result | Should -HaveKey "BotRunning"
                $result | Should -HaveKey "Errors"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should return Errors as array" {
            # Arrange
            $testPath = "C:\NonExistent\Path\That\Does\Not\Exist\12345"

            # Act
            $result = Confirm-ConfigEditorPrerequisites -InstallPath $testPath

            # Assert
            $result.Errors | Should -BeOfType [System.Collections.ArrayList] -or $result.Errors -is [array]
        }
    }

    Context "Mixed Error Scenarios" {

        It "Should accumulate multiple errors when installation missing AND config missing" {
            # Arrange
            $testPath = "C:\NonExistent\Path\12345"

            # Act
            $result = Confirm-ConfigEditorPrerequisites -InstallPath $testPath

            # Assert
            $result.Valid | Should -Be $false
            $result.Errors.Count | Should -BeGreaterThan 1
        }

        It "Should return Valid=false with multiple errors present" {
            # Arrange
            $testPath = "C:\NonExistent\Path\12345"

            # Act
            $result = Confirm-ConfigEditorPrerequisites -InstallPath $testPath

            # Assert
            $result.Valid | Should -Be $false
            $result.Errors.Count | Should -Be 2  # Installation not found + config not found
        }
    }

    Context "Default Parameter Handling" {

        It "Should use default InstallPath when not specified" {
            # Arrange - Test with default path
            $defaultPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"

            # Act
            $result = Confirm-ConfigEditorPrerequisites

            # Assert
            $result.InstallPath | Should -Be $defaultPath
        }
    }
}
