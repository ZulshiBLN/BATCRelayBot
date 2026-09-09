#Requires -Modules Pester

Describe "Config File Safety Functions" {

    BeforeAll {
        # Import the module rather than dot-sourcing individual files, the way
        # every other test file does. Dot-sourcing broke as soon as these
        # functions started calling shared helpers - each file would have to
        # be sourced in dependency order - and it fails outright on any file
        # containing Export-ModuleMember, which only works inside a module.
        Import-Module "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1" -Force
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
                bot_token         = "abc123def456"
                guild_id  = 123456789012345678
                audio_device_name = "Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)"
            }
            $config | ConvertTo-Json | Set-Content -Path $configFile -Force

            try {
                # Act
                $result = Update-ConfigJson -ConfigPath $configFile -Field "Token" -Value "newtoken123"

                # Assert
                $result | Should -Not -Be $null
                $result | Should -Match '"bot_token":'
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
            @{ bot_token = "oldtoken"; guild_id = "123456789012345678" } | ConvertTo-Json | Set-Content $configFile

            try {
                # Act
                $newJson = Update-ConfigJson -ConfigPath $configFile -Field "Token" -Value "newtoken456"
                $parsed = $newJson | ConvertFrom-Json

                # Assert
                $parsed.bot_token | Should -Be "newtoken456"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should update guild_id field correctly" {
            # Was written against voice_channel_id, which the editor no longer
            # offers - the channel is decided per !BATCjoin. guild_id is the
            # remaining numeric ID and exercises the same path.
            $testDir = Join-Path $env:TEMP "ConfigUpdateTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{ bot_token = "abc"; guild_id = "111111111111111111" } | ConvertTo-Json | Set-Content $configFile

            try {
                $newJson = Update-ConfigJson -ConfigPath $configFile -Field "Guild" -Value "999999999999999999"
                $parsed = $newJson | ConvertFrom-Json

                $parsed.guild_id | Should -Be "999999999999999999"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should refuse fields the bot does not read" {
            # output_format and bot_activity were editable before 1.4.0 but
            # appear nowhere in bot.py, so writing them changed nothing while
            # looking like it had worked. They are rejected outright now.
            $testDir = Join-Path $env:TEMP "ConfigUpdateTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{ bot_token = "abc"; voice_channel_id = 123456789012345678 } | ConvertTo-Json | Set-Content $configFile

            try {
                { Update-ConfigJson -ConfigPath $configFile -Field "Format" -Value "verbose" } | Should -Throw
                { Update-ConfigJson -ConfigPath $configFile -Field "Activity" -Value "flying" } | Should -Throw
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should update audio_device_name field correctly" {
            # The field most likely to need correcting after an install: it
            # decides whether anything is heard at all.
            $testDir = Join-Path $env:TEMP "ConfigUpdateTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{ audio_device_name = "Voicemeeter Out B3 (VB-Audio Voicemeeter VAIO)" } |
                ConvertTo-Json | Set-Content $configFile

            try {
                $newJson = Update-ConfigJson -ConfigPath $configFile `
                    -Field "AudioDevice" -Value "Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)"
                $parsed = $newJson | ConvertFrom-Json

                $parsed.audio_device_name | Should -Be "Voicemeeter Out B1 (VB-Audio Voicemeeter VAIO)"
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
            # A path inside a directory that does not exist fails the same way
            # for every caller. The previous version targeted
            # C:\Windows\System32, which only fails when the process is not
            # elevated - on the CI runner it is, so the write succeeded, the
            # test failed, and it left a file behind in System32.
            $unwritablePath = Join-Path $env:TEMP "no-such-dir-$([guid]::NewGuid())\config.json"

            { Write-ConfigFile -ConfigPath $unwritablePath -JsonContent '{}' } | Should -Throw
        }
    }

    Context "Verify-ConfigChange - Re-read & Compare" {

        It "Should verify written value matches expected value" {
            # Arrange
            $testDir = Join-Path $env:TEMP "ConfigVerifyTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{ bot_token = "newtoken123" } | ConvertTo-Json | Set-Content $configFile

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
            @{ bot_token = "wrong_value" } | ConvertTo-Json | Set-Content $configFile

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
                $result.Message | Should -Match "could not be read back"
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
                @{ bot_token = "wrong_value" } | ConvertTo-Json | Set-Content $configFile

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
