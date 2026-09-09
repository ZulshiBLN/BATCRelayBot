# Phase 3 of the installer: what happens when Python or FFmpeg is missing.
#
# It printed the same four lines twice. Declining the winget offer showed the
# download links, returned, and then the caller found the tools still missing
# and printed its own copy of them. The links now live in exactly one function.
#
# The third menu option, "Continue without installing", is gone. The bot cannot
# run without either tool, so continuing only moved the failure further from its
# cause - see rules/installer.md.

BeforeAll {
    $ModuleRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'BATCRelayBot'
    Import-Module (Join-Path $ModuleRoot 'BATCRelayBot.psm1') -Force

    $InstallerSource = Get-Content (Join-Path $ModuleRoot 'Public\Install-BATCRelayBot.ps1') -Raw

    function Get-Links {
        param([bool]$PythonFound, [bool]$FFmpegFound)
        $prereq = @{
            Python = @{ Found = $PythonFound }
            FFmpeg = @{ Found = $FFmpegFound }
        }
        ((Show-ManualInstallLinks -Prerequisites $prereq 6>&1) | ForEach-Object { "$_" }) -join "`n"
    }
}

Describe "Show-ManualInstallLinks" {

    It "writes nothing to the success stream" {
        @(Show-ManualInstallLinks -Prerequisites @{
            Python = @{ Found = $false }; FFmpeg = @{ Found = $false }
        } 6>$null).Count | Should -Be 0
    }

    It "names only what is actually missing" {
        $onlyPython = Get-Links -PythonFound $false -FFmpegFound $true
        $onlyPython | Should -Match 'python\.org'
        $onlyPython | Should -Not -Match 'Gyan\.FFmpeg'

        $onlyFFmpeg = Get-Links -PythonFound $true -FFmpegFound $false
        $onlyFFmpeg | Should -Match 'Gyan\.FFmpeg'
        $onlyFFmpeg | Should -Not -Match 'python\.org'
    }

    It "says how to continue" {
        Get-Links -PythonFound $false -FFmpegFound $false |
            Should -Match 'Run Install-BATCRelayBot again'
    }

    # The duplication itself, asserted where it can be counted: if a second copy
    # of the links appears anywhere in the module, this fails.
    It "is the only place in the module that prints these links" {
        foreach ($link in 'python\.org/downloads', 'ffmpeg\.org/download') {
            $hits = @(Get-ChildItem $ModuleRoot -Filter *.ps1 -Recurse |
                Select-String -Pattern $link)
            $hits.Count | Should -Be 1 -Because "$link should be printed from one place"
        }
    }
}

Describe "Resolving missing tools" {

    It "offers no way to continue without Python or FFmpeg" {
        $InstallerSource | Should -Not -Match '(?i)continue without installing'
    }

    It "asks once, and defaults to installing" {
        $resolve = [regex]::Match($InstallerSource,
            '(?s)function Resolve-MissingTool.*?\n\}').Value

        ([regex]::Matches($resolve, 'Read-Host')).Count | Should -Be 1
        $resolve | Should -Match '\(Y/n\)'
    }

    It "reports the log file in words rather than raw" {
        $InstallerSource | Should -Match 'Logfile created under'
        $InstallerSource | Should -Not -Match '"Log file: '
    }
}
