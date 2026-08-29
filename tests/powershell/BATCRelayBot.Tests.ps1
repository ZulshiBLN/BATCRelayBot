BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "..\..\BATCRelayBot\BATCRelayBot.psd1"
    Import-Module $ModulePath -Force
}

Describe "BATCRelayBot Module" {
    Context "Module Import" {
        It "Should import without errors" {
            { Import-Module $ModulePath -Force } | Should -Not -Throw
        }

        It "Should be loaded" {
            Get-Module BATCRelayBot | Should -Not -BeNullOrEmpty
        }

        It "Should have correct module name" {
            (Get-Module BATCRelayBot).Name | Should -Be "BATCRelayBot"
        }
    }

    Context "Exported Functions" {
        It "Should export Install-BATCRelayBot" {
            Get-Command Install-BATCRelayBot -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should export Start-BATCRelayBot" {
            Get-Command Start-BATCRelayBot -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should export Stop-BATCRelayBot" {
            Get-Command Stop-BATCRelayBot -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should export Get-BATCRelayBotStatus" {
            Get-Command Get-BATCRelayBotStatus -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should export Uninstall-BATCRelayBot" {
            Get-Command Uninstall-BATCRelayBot -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have exactly 5 exported functions" {
            @(Get-Command -Module BATCRelayBot).Count | Should -Be 5
        }
    }

    Context "Function Documentation" {
        It "Install-BATCRelayBot should have help" {
            (Get-Help Install-BATCRelayBot).Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Start-BATCRelayBot should have help" {
            (Get-Help Start-BATCRelayBot).Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Stop-BATCRelayBot should have help" {
            (Get-Help Stop-BATCRelayBot).Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Get-BATCRelayBotStatus should have help" {
            (Get-Help Get-BATCRelayBotStatus).Synopsis | Should -Not -BeNullOrEmpty
        }

        It "Uninstall-BATCRelayBot should have help" {
            (Get-Help Uninstall-BATCRelayBot).Synopsis | Should -Not -BeNullOrEmpty
        }
    }

    Context "Function Parameters" {
        It "Install-BATCRelayBot should have BotPath parameter" {
            (Get-Command Install-BATCRelayBot).Parameters.Keys | Should -Contain "BotPath"
        }

        It "Start-BATCRelayBot should exist and be callable" {
            { Get-Command Start-BATCRelayBot } | Should -Not -Throw
        }

        It "Stop-BATCRelayBot should exist and be callable" {
            { Get-Command Stop-BATCRelayBot } | Should -Not -Throw
        }

        It "Get-BATCRelayBotStatus should exist and be callable" {
            { Get-Command Get-BATCRelayBotStatus } | Should -Not -Throw
        }

        It "Uninstall-BATCRelayBot should exist and be callable" {
            { Get-Command Uninstall-BATCRelayBot } | Should -Not -Throw
        }
    }

    Context "Module Properties" {
        It "Should have Author" {
            (Get-Module BATCRelayBot).Author | Should -Not -BeNullOrEmpty
        }

        It "Should have Description" {
            (Get-Module BATCRelayBot).Description | Should -Not -BeNullOrEmpty
        }

        It "Should have correct PowerShell version requirement" {
            (Get-Module BATCRelayBot).PowerShellVersion | Should -Be "5.1"
        }
    }

    Context "RootModule" {
        It "Should have RootModule defined" {
            $manifest = Test-ModuleManifest -Path $ModulePath
            $manifest.RootModule | Should -Not -BeNullOrEmpty
        }

        It "Should load RootModule correctly" {
            $manifest = Test-ModuleManifest -Path $ModulePath
            $manifest.RootModule | Should -Match "BATCRelayBot.psm1"
        }
    }
}
