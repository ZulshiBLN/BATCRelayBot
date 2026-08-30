#Requires -Modules Pester

Describe "Confirm-ConfigEditorPrerequisites" {

    BeforeAll {
        $functionPath = "$PSScriptRoot\..\..\BATCRelayBot\Private\Confirm-ConfigEditorPrerequisites.ps1"
        if (Test-Path $functionPath) {
            . $functionPath
        }
    }

    Context "Installation Directory Validation" {

        It "Should return Valid=true when installation directory exists" {
            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir
                $result.Valid | Should -Be $true
                $result.InstallPath | Should -Be $testDir
                $result.Errors.Count | Should -Be 0
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should return Valid=false and error when installation directory not found" {
            $testPath = "C:\NonExistent\Path\That\Does\Not\Exist\12345"
            $result = Confirm-ConfigEditorPrerequisites -InstallPath $testPath

            $result.Valid | Should -Be $false
            $result.Errors[0] | Should -Match "Installation directory not found"
        }
    }

    Context "config.json File Existence" {

        It "Should return Valid=false when config.json not found" {
            $testPath = $env:TEMP
            $result = Confirm-ConfigEditorPrerequisites -InstallPath $testPath

            $result.Valid | Should -Be $false
            $result.Errors[0] | Should -Match "config.json not found"
        }

        It "Should return ConfigPath when config.json exists" {
            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir
                $result.ConfigPath | Should -Be $configFile
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "File Permissions - Read/Write Access" {

        It "Should return Valid=true when config.json is readable and writable" {
            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir
                $result.Valid | Should -Be $true
                ($result.Errors -match "permissions").Count | Should -Be 0
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Bot Running Status Detection" {

        It "Should return BotRunning=false when bot process not running" {
            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir
                $result.BotRunning | Should -Be $false
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should detect bot running status correctly" {
            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir
                $result.BotRunning | Should -BeOfType [bool]
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Return Value Structure" {

        It "Should return hashtable with all required properties" {
            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir
                $result.Keys -contains "Valid" | Should -Be $true
                $result.Keys -contains "InstallPath" | Should -Be $true
                $result.Keys -contains "ConfigPath" | Should -Be $true
                $result.Keys -contains "BotRunning" | Should -Be $true
                $result.Keys -contains "Errors" | Should -Be $true
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should return Errors collection" {
            $testPath = "C:\NonExistent\Path\12345"
            $result = Confirm-ConfigEditorPrerequisites -InstallPath $testPath

            $result.Errors | Should -Not -Be $null
            $result.Errors -is [System.Collections.ICollection] | Should -Be $true
        }
    }

    Context "Mixed Error Scenarios" {

        It "Should accumulate multiple errors when installation missing" {
            $testPath = "C:\NonExistent\Path\12345"
            $result = Confirm-ConfigEditorPrerequisites -InstallPath $testPath

            $result.Valid | Should -Be $false
            $result.Errors.Count | Should -BeGreaterThan 1
        }

        It "Should include both installation and config errors" {
            $testPath = "C:\NonExistent\Path\12345"
            $result = Confirm-ConfigEditorPrerequisites -InstallPath $testPath

            $result.Valid | Should -Be $false
            $result.Errors.Count | Should -Be 2
            $result.Errors[0] | Should -Match "Installation directory not found"
            $result.Errors[1] | Should -Match "config.json not found"
        }
    }

    Context "Default Parameter Handling" {

        It "Should use default InstallPath when not specified" {
            $defaultPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
            $result = Confirm-ConfigEditorPrerequisites

            $result.InstallPath | Should -Be $defaultPath
        }
    }

    Context "Valid Configuration Results" {

        It "Should report Valid=true only when ALL checks pass" {
            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir
                $result.Valid | Should -Be $true
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should return ConfigPath only when Valid=true" {
            $testDir = Join-Path $env:TEMP "ConfigEditorTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir
                $result.Valid | Should -Be $true
                $result.ConfigPath | Should -Not -Be $null
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
