#Requires -Modules Pester

Describe "Edit-BATCRelayBotConfig - Integration Tests" {

    BeforeAll {
        $privatePath = "$PSScriptRoot\..\..\BATCRelayBot\Private"
        $publicPath = "$PSScriptRoot\..\..\BATCRelayBot\Public"

        $functionFiles = @(
            "Confirm-ConfigEditorPrerequisites.ps1",
            "Show-ConfigEditorMenu.ps1",
            "Get-DiscordToken.ps1",
            "Get-DiscordChannel.ps1",
            "Get-OutputFormat.ps1",
            "Get-BotActivity.ps1",
            "Test-ConfigValue.ps1",
            "Backup-ConfigFile.ps1",
            "Update-ConfigJson.ps1",
            "Write-ConfigFile.ps1",
            "Verify-ConfigChange.ps1",
            "Edit-BATCRelayBotConfig.ps1"
        )

        foreach ($file in $functionFiles) {
            $paths = @("$privatePath\$file", "$publicPath\$file")
            foreach ($path in $paths) {
                if (Test-Path $path) {
                    . $path
                    break
                }
            }
        }
    }

    Context "Full Configuration Editor Workflow" {

        It "Should validate prerequisites before allowing edit" {
            $testDir = Join-Path $env:TEMP "ConfigIntTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{
                token = "oldtoken"
                channel_id = "111111111111111111"
                output_format = "standard"
                bot_activity = "Testing"
            } | ConvertTo-Json | Set-Content $configFile

            try {
                $result = Confirm-ConfigEditorPrerequisites -InstallPath $testDir
                $result.Valid | Should -Be $true
                Test-Path $result.ConfigPath | Should -Be $true
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should complete edit flow: backup → update → write → verify" {
            $testDir = Join-Path $env:TEMP "ConfigIntTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{
                token = "oldtoken123"
                channel_id = "111111111111111111"
                output_format = "standard"
                bot_activity = "Testing"
            } | ConvertTo-Json | Set-Content $configFile

            try {
                # Simulate full flow
                $backup = Backup-ConfigFile -ConfigPath $configFile
                $newJson = Update-ConfigJson -ConfigPath $configFile -Field "Token" -Value "newtoken456"
                $written = Write-ConfigFile -ConfigPath $configFile -JsonContent $newJson
                $verify = Verify-ConfigChange -ConfigPath $configFile -Field "Token" -ExpectedValue "newtoken456"

                $backup | Should -Not -Be $null
                Test-Path $backup | Should -Be $true
                $written | Should -Be $true
                $verify.Verified | Should -Be $true
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should handle multiple sequential edits" {
            $testDir = Join-Path $env:TEMP "ConfigIntTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            @{
                token = "token1"
                channel_id = "111111111111111111"
                output_format = "standard"
                bot_activity = "Test1"
            } | ConvertTo-Json | Set-Content $configFile

            try {
                # Edit 1: Token
                $json1 = Update-ConfigJson -ConfigPath $configFile -Field "Token" -Value "token2"
                Write-ConfigFile -ConfigPath $configFile -JsonContent $json1

                # Edit 2: Channel
                $json2 = Update-ConfigJson -ConfigPath $configFile -Field "Channel" -Value "222222222222222222"
                Write-ConfigFile -ConfigPath $configFile -JsonContent $json2

                # Edit 3: Activity
                $json3 = Update-ConfigJson -ConfigPath $configFile -Field "Activity" -Value "Test3"
                Write-ConfigFile -ConfigPath $configFile -JsonContent $json3

                # Verify all changes
                $final = Get-Content $configFile -Raw | ConvertFrom-Json
                $final.token | Should -Be "token2"
                $final.channel_id | Should -Be "222222222222222222"
                $final.bot_activity | Should -Be "Test3"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should rollback automatically on verification failure" {
            $testDir = Join-Path $env:TEMP "ConfigIntTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            $originalToken = "originaltoken"
            @{ token = $originalToken } | ConvertTo-Json | Set-Content $configFile

            try {
                # Backup original
                $backup = Backup-ConfigFile -ConfigPath $configFile

                # Write wrong value
                @{ token = "wrongtoken" } | ConvertTo-Json | Set-Content $configFile

                # Verify should fail
                $verify = Verify-ConfigChange -ConfigPath $configFile -Field "Token" -ExpectedValue "expectedtoken"
                $verify.Verified | Should -Be $false

                # Rollback
                Copy-Item $backup $configFile -Force
                $restored = Get-Content $configFile -Raw | ConvertFrom-Json
                $restored.token | Should -Be $originalToken
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Should create backups with proper naming convention" {
            $testDir = Join-Path $env:TEMP "ConfigIntTest_$([System.Guid]::NewGuid())"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $configFile = Join-Path $testDir "config.json"
            [System.IO.File]::WriteAllText($configFile, "{}")

            try {
                # Create a backup
                $backup = Backup-ConfigFile -ConfigPath $configFile

                # Should have backup-YYYYMMDD-HHmmss format
                $backup | Should -Match "backup-\d{8}-\d{6}"
                Test-Path $backup | Should -Be $true

                # Content should match original
                (Get-Content $backup -Raw) | Should -Be "{}"
            }
            finally {
                Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
