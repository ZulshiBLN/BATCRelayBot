#Requires -Modules Pester

Describe "Config File Safety Functions" {

    BeforeAll {
        $privatePath = "$PSScriptRoot\..\..\BATCRelayBot\Private"

        $functionFiles = @(
            "Backup-ConfigFile.ps1",
            "Update-ConfigJson.ps1",
            "Write-ConfigFile.ps1",
            "Verify-ConfigChange.ps1"
        )

        foreach ($file in $functionFiles) {
            $path = Join-Path $privatePath $file
            if (Test-Path $path) {
                . $path
            }
        }
    }

    Context "Backup-ConfigFile - Create Timestamped Backups" {

        It "Should create backup file with timestamp" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigBackupTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{`"test`": `"value`"}" -Force

            try {
                # Act
                $backup = Backup-ConfigFile -ConfigPath $configFile

                # Assert
                $backup | Should -Not -Be $null
                Test-Path $backup | Should -Be $true
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should include timestamp in backup filename" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigBackupTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                # Act
                $backup = Backup-ConfigFile -ConfigPath $configFile

                # Assert - Should have format: config.json.backup-YYYYMMDD-HHmmss
                $backup | Should -Match "backup-\d{8}-\d{6}"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should preserve original file content in backup" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigBackupTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            $originalContent = "{`"key`": `"value`"}"
            [System.IO.File]::WriteAllText($configFile, $originalContent)

            try {
                # Act
                $backup = Backup-ConfigFile -ConfigPath $configFile
                $backupContent = Get-Content $backup -Raw

                # Assert - trim CRLF for comparison
                $backupContent.Trim() | Should -Be $originalContent
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should clean up old backups keeping only last 10" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigBackupTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            [System.IO.File]::WriteAllText($configFile, "{}")

            # Create 15 mock backup files
            for ($i = 1; $i -le 15; $i++) {
                $backupName = "config.json.backup-2026083001-12000$i"
                New-Item -Path $testDir -Name $backupName -ItemType File -Force | Out-Null
            }

            try {
                # Act
                $backup = Backup-ConfigFile -ConfigPath $configFile

                # Assert - Should have at most 11 backups (10 old + 1 new)
                $backupCount = @(Get-ChildItem $testDir -Filter "config.json.backup-*").Count
                if ($backupCount -lt 2) { $backupCount = 1 }
                ($backupCount -le 11) | Should -Be $true
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should return backup file path" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigBackupTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{}" -Force

            try {
                # Act
                $result = Backup-ConfigFile -ConfigPath $configFile

                # Assert
                $result | Should -BeOfType [string]
                $result.Length -gt 0 | Should -Be $true
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Update-ConfigJson - Merge New Values" {

        It "Should parse valid JSON config file" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigUpdateTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            $config = @{
                token = "abc123def456"
                channel_id = "123456789012345678"
                output_format = "standard"
                bot_activity = "Flying sim"
            }
            $config | ConvertTo-Json | Set-Content -Path $configFile -Force

            try {
                # Act
                $result = Update-ConfigJson -ConfigPath $configFile -Field "Token" -Value "newtoken123"

                # Assert
                $result | Should -Not -Be $null
                $result | Should -Match '"token":'
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should update token field correctly" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigUpdateTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{ token = "oldtoken"; channel_id = "123456789012345678" } | ConvertTo-Json | Set-Content $configFile

            try {
                # Act
                $newJson = Update-ConfigJson -ConfigPath $configFile -Field "Token" -Value "newtoken456"
                $parsed = $newJson | ConvertFrom-Json

                # Assert
                $parsed.token | Should -Be "newtoken456"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should update channel_id field correctly" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigUpdateTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{ token = "abc"; channel_id = "111111111111111111" } | ConvertTo-Json | Set-Content $configFile

            try {
                # Act
                $newJson = Update-ConfigJson -ConfigPath $configFile -Field "Channel" -Value "999999999999999999"
                $parsed = $newJson | ConvertFrom-Json

                # Assert
                $parsed.channel_id | Should -Be "999999999999999999"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should update output_format field correctly" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigUpdateTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{ output_format = "standard" } | ConvertTo-Json | Set-Content $configFile

            try {
                # Act
                $newJson = Update-ConfigJson -ConfigPath $configFile -Field "Format" -Value "verbose"
                $parsed = $newJson | ConvertFrom-Json

                # Assert
                $parsed.output_format | Should -Be "verbose"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should update bot_activity field correctly" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigUpdateTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{ bot_activity = "Old activity" } | ConvertTo-Json | Set-Content $configFile

            try {
                # Act
                $newJson = Update-ConfigJson -ConfigPath $configFile -Field "Activity" -Value "New activity"
                $parsed = $newJson | ConvertFrom-Json

                # Assert
                $parsed.bot_activity | Should -Be "New activity"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should handle invalid JSON gracefully" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigUpdateTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{ invalid json }" -Force

            try {
                # Act & Assert
                { Update-ConfigJson -ConfigPath $configFile -Field "Token" -Value "test" } | Should -Throw
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Write-ConfigFile - Atomic File Write" {

        It "Should write JSON content to file atomically" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigWriteTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            $jsonContent = '{"token":"abc123","channel_id":"123456789012345678"}'

            try {
                # Act
                $result = Write-ConfigFile -ConfigPath $configFile -JsonContent $jsonContent

                # Assert
                $result | Should -Be $true
                Test-Path $configFile | Should -Be $true
                (Get-Content $configFile -Raw) | Should -Be $jsonContent
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should cleanup temp file on success" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigWriteTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"

            try {
                # Act
                Write-ConfigFile -ConfigPath $configFile -JsonContent '{"test":"value"}'

                # Assert - temp file should not exist
                Test-Path "$configFile.tmp" | Should -Be $false
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should handle write errors gracefully" {
            # Arrange - use read-only path
            $readOnlyPath = "C:\Windows\System32\test_readonly_config.json"

            # Act & Assert
            { Write-ConfigFile -ConfigPath $readOnlyPath -JsonContent '{}' } | Should -Throw
        }
    }

    Context "Verify-ConfigChange - Re-read & Compare" {

        It "Should verify written value matches expected value" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigVerifyTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{ token = "newtoken123" } | ConvertTo-Json | Set-Content $configFile

            try {
                # Act
                $result = Verify-ConfigChange -ConfigPath $configFile -Field "Token" -ExpectedValue "newtoken123"

                # Assert
                $result.Verified | Should -Be $true
                $result.WrittenValue | Should -Be "newtoken123"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should detect value mismatch after write" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigVerifyTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{ token = "wrong_value" } | ConvertTo-Json | Set-Content $configFile

            try {
                # Act
                $result = Verify-ConfigChange -ConfigPath $configFile -Field "Token" -ExpectedValue "expected_value"

                # Assert
                $result.Verified | Should -Be $false
                $result.WrittenValue | Should -Be "wrong_value"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should handle JSON parse errors" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigVerifyTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            Set-Content -Path $configFile -Value "{ invalid json" -Force

            try {
                # Act
                $result = Verify-ConfigChange -ConfigPath $configFile -Field "Token" -ExpectedValue "test"

                # Assert
                $result.Verified | Should -Be $false
                $result.Message | Should -Match "JSON parse error"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should return structured result object" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigVerifyTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{ channel_id = "123456789012345678" } | ConvertTo-Json | Set-Content $configFile

            try {
                # Act
                $result = Verify-ConfigChange -ConfigPath $configFile -Field "Channel" -ExpectedValue "123456789012345678"

                # Assert
                $result.Keys -contains "Verified" | Should -Be $true
                $result.Keys -contains "WrittenValue" | Should -Be $true
                $result.Keys -contains "Message" | Should -Be $true
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Integration - Full Save & Verify Workflow" {

        It "Should complete full backup→update→write→verify flow" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigIntegrationTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            $config = @{
                token = "oldtoken"
                channel_id = "111111111111111111"
                output_format = "standard"
                bot_activity = "Streaming"
            }
            $config | ConvertTo-Json | Set-Content $configFile

            try {
                # Act
                $backup = Backup-ConfigFile -ConfigPath $configFile
                $newJson = Update-ConfigJson -ConfigPath $configFile -Field "Token" -Value "newtoken123"
                $written = Write-ConfigFile -ConfigPath $configFile -JsonContent $newJson
                $verified = Verify-ConfigChange -ConfigPath $configFile -Field "Token" -ExpectedValue "newtoken123"

                # Assert
                $backup | Should -Not -Be $null
                Test-Path $backup | Should -Be $true
                $written | Should -Be $true
                $verified.Verified | Should -Be $true
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should rollback on verification failure" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigRollbackTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{ token = "original" } | ConvertTo-Json | Set-Content $configFile
            $backup = Backup-ConfigFile -ConfigPath $configFile

            try {
                # Act - Write wrong value
                @{ token = "wrong_value" } | ConvertTo-Json | Set-Content $configFile

                # Verify should fail
                $verify = Verify-ConfigChange -ConfigPath $configFile -Field "Token" -ExpectedValue "expected"
                if (-not $verify.Verified) {
                    # Rollback
                    Copy-Item $backup $configFile -Force
                }

                # Assert - original restored
                $restored = Get-Content $configFile -Raw | ConvertFrom-Json
                $restored.token | Should -Be "original"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
