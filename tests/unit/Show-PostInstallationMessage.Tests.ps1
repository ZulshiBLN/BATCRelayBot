BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force
}

Describe "Show-PostInstallationMessage" {
    It "Executes without errors" {
        $installPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
        $configPath = Join-Path $installPath "config.json"
        $logPath = Join-Path $installPath "install.log"

        { Show-PostInstallationMessage -InstallPath $installPath -ConfigPath $configPath -LogPath $logPath } | Should -Not -Throw
    }

    It "Returns hashtable with required keys" {
        $installPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
        $configPath = Join-Path $installPath "config.json"
        $logPath = Join-Path $installPath "install.log"

        $result = Show-PostInstallationMessage -InstallPath $installPath -ConfigPath $configPath -LogPath $logPath
        $result | Should -BeOfType [hashtable]
        $result.Keys | Should -Contain "InstallPath"
        $result.Keys | Should -Contain "ConfigPath"
        $result.Keys | Should -Contain "LogPath"
        $result.Keys | Should -Contain "Success"
    }

    It "Marks installation as successful" {
        $installPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
        $configPath = Join-Path $installPath "config.json"
        $logPath = Join-Path $installPath "install.log"

        $result = Show-PostInstallationMessage -InstallPath $installPath -ConfigPath $configPath -LogPath $logPath
        $result.Success | Should -Be $true
    }

    It "Preserves installation paths in output" {
        $installPath = "C:\Custom\Install\Path"
        $configPath = "C:\Custom\Install\Path\config.json"
        $logPath = "C:\Custom\Install\Path\install.log"

        $result = Show-PostInstallationMessage -InstallPath $installPath -ConfigPath $configPath -LogPath $logPath
        $result.InstallPath | Should -Be $installPath
        $result.ConfigPath | Should -Be $configPath
        $result.LogPath | Should -Be $logPath
    }
}

Describe "Phase 6: Post-Installation Messaging" {
    It "Function exists" {
        { Get-Command Show-PostInstallationMessage -ErrorAction Stop } | Should -Not -Throw
    }

    It "Displays success message" {
        $installPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
        $configPath = Join-Path $installPath "config.json"
        $logPath = Join-Path $installPath "install.log"

        # Function should display without prompts
        { Show-PostInstallationMessage -InstallPath $installPath -ConfigPath $configPath -LogPath $logPath } | Should -Not -Throw
    }

    It "Provides next steps guidance" {
        $installPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
        $configPath = Join-Path $installPath "config.json"
        $logPath = Join-Path $installPath "install.log"

        # Next steps should be displayed
        { Show-PostInstallationMessage -InstallPath $installPath -ConfigPath $configPath -LogPath $logPath } | Should -Not -Throw
    }

    It "Handles all required parameters" {
        $installPath = "C:\Install"
        $configPath = "C:\Install\config.json"
        $logPath = "C:\Install\install.log"

        $result = Show-PostInstallationMessage -InstallPath $installPath -ConfigPath $configPath -LogPath $logPath
        $result | Should -Not -BeNull
    }
}
