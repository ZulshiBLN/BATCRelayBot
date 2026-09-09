#Requires -Version 5.1

<#
.SYNOPSIS
Regression tests for the uninstaller bugs found during local testing in 1.4.0.

.DESCRIPTION
Each block pins one defect that made the uninstaller unable to remove what the
user had confirmed:

  - only the literal string "yes" was accepted, so "y" silently meant no
  - presence was decided with `winget show`, which queries the catalogue and
    therefore succeeds for packages that are not installed
  - the removal used a package id that does not exist (Python.Python instead
    of Python.Python.3.12), and native commands do not throw, so the
    surrounding try/catch never fired and success was always reported
  - process detection used Get-Process | Where CommandLine, a property that
    does not exist on Windows PowerShell 5.1
#>

BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1"
    Import-Module $modulePath -Force
}

Describe "Read-YesNo" {

    It "accepts the short form, which used to be read as a silent no" {
        foreach ($answer in @('y', 'Y', 'j', 'J')) {
            Mock -ModuleName BATCRelayBot Read-Host { $answer }.GetNewClosure()
            Read-YesNo -Question "Remove?" | Should -BeTrue -Because "'$answer' means yes"
        }
    }

    It "accepts the long form in English and German" {
        foreach ($answer in @('yes', 'YES', 'Yes', 'ja', 'Ja')) {
            Mock -ModuleName BATCRelayBot Read-Host { $answer }.GetNewClosure()
            Read-YesNo -Question "Remove?" | Should -BeTrue -Because "'$answer' means yes"
        }
    }

    It "treats anything else as no" {
        foreach ($answer in @('n', 'no', 'nein', 'maybe', 'yeah', 'yolo')) {
            Mock -ModuleName BATCRelayBot Read-Host { $answer }.GetNewClosure()
            Read-YesNo -Question "Remove?" | Should -BeFalse -Because "'$answer' is not a yes"
        }
    }

    It "defaults to no on empty input" {
        Mock -ModuleName BATCRelayBot Read-Host { "" }
        Read-YesNo -Question "Remove?" | Should -BeFalse
    }

    It "ignores surrounding whitespace" {
        Mock -ModuleName BATCRelayBot Read-Host { "  yes  " }
        Read-YesNo -Question "Remove?" | Should -BeTrue
    }
}

Describe "ConvertFrom-WingetListOutput" {

    # Captured verbatim from `winget list --id Python.Python` on Windows 11.
    BeforeAll {
        $script:PythonOutput = @(
            'Name                    Id                 Version Source',
            '----------------------------------------------------------',
            'Python 3.12.10 (64-bit) Python.Python.3.12 3.12.10 winget'
        )
    }

    It "extracts the full package id, not the prefix that was searched for" {
        # winget uninstall "Python.Python" matches nothing; the installed id
        # carries the version suffix.
        $packages = @(ConvertFrom-WingetListOutput -Lines $script:PythonOutput -IdPattern 'Python\.Python\.[\d.]+')
        $packages.Count | Should -Be 1
        $packages[0].Id | Should -Be 'Python.Python.3.12'
    }

    It "reads the version from the row" {
        $packages = @(ConvertFrom-WingetListOutput -Lines $script:PythonOutput -IdPattern 'Python\.Python\.[\d.]+')
        $packages[0].Version | Should -Be '3.12.10'
    }

    It "returns nothing when the pattern does not appear" {
        $packages = @(ConvertFrom-WingetListOutput -Lines $script:PythonOutput -IdPattern 'Gyan\.FFmpeg\S*')
        $packages.Count | Should -Be 0
    }

    It "does not mistake the 'no package found' message for a package" {
        $notFound = @('No installed package found matching input criteria.')
        $packages = @(ConvertFrom-WingetListOutput -Lines $notFound -IdPattern 'Gyan\.FFmpeg\S*')
        $packages.Count | Should -Be 0
    }

    It "lists several versions separately so each can be removed on its own" {
        $twoVersions = @(
            'Python 3.11.9 (64-bit)  Python.Python.3.11 3.11.9  winget',
            'Python 3.12.10 (64-bit) Python.Python.3.12 3.12.10 winget'
        )
        $packages = @(ConvertFrom-WingetListOutput -Lines $twoVersions -IdPattern 'Python\.Python\.[\d.]+')
        $packages.Count | Should -Be 2
        $packages.Id | Should -Contain 'Python.Python.3.11'
        $packages.Id | Should -Contain 'Python.Python.3.12'
    }

    It "tolerates a row with no version column" {
        $packages = @(ConvertFrom-WingetListOutput -Lines @('Gyan.FFmpeg') -IdPattern 'Gyan\.FFmpeg\S*')
        $packages.Count | Should -Be 1
        $packages[0].Version | Should -Be 'unknown'
    }
}

Describe "Find-BotProcess" {

    It "returns nothing for a path where no bot was ever installed" {
        $absent = Join-Path ([System.IO.Path]::GetTempPath()) "batc-no-such-install-$([guid]::NewGuid())"
        @(Find-BotProcess -BotPath $absent).Count | Should -Be 0
    }

    # The last-resort branch matches a bare "bot.py" command line, because a
    # bot started from its own directory records no path anywhere the process
    # list can be asked about. It used to do that for any path it was given,
    # so an empty directory reported a bot, and one installation's uninstaller
    # would stop another installation's process. It also made this file's
    # tests depend on whether a bot happened to be running on the machine -
    # which they did, intermittently, on 2026-09-09.
    #
    # Mocked rather than started for real: the point is what the matching does
    # with a given process list, not whether python can be launched.
    Context "a bare bot.py command line" {

        BeforeAll {
            $script:Elsewhere = @([pscustomobject]@{
                Name           = 'python.exe'
                ProcessId      = 4242
                CommandLine    = 'python bot.py'
                ExecutablePath = 'C:\Python312\python.exe'
            })
        }

        It "is not claimed for a directory that holds no bot" {
            InModuleScope BATCRelayBot -Parameters @{ Processes = $script:Elsewhere } {
                param($Processes)
                Mock Get-CimInstance { $Processes }

                $empty = Join-Path $env:TEMP ("nobot-" + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $empty -Force | Out-Null
                try {
                    @(Find-BotProcess -BotPath $empty).Count | Should -Be 0
                } finally {
                    Remove-Item $empty -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        It "is claimed for a directory that does hold one" {
            InModuleScope BATCRelayBot -Parameters @{ Processes = $script:Elsewhere } {
                param($Processes)
                Mock Get-CimInstance { $Processes }

                $installed = Join-Path $env:TEMP ("withbot-" + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $installed -Force | Out-Null
                "print('bot')" | Set-Content (Join-Path $installed 'bot.py')
                try {
                    @(Find-BotProcess -BotPath $installed) | Should -Be @(4242)
                } finally {
                    Remove-Item $installed -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    It "looks at pythonw.exe as well as python.exe" {
        # Start-BATCRelayBot launches the windowless interpreter, so a
        # detector that only knows python.exe never sees a backgrounded bot.
        $source = Get-Content "$PSScriptRoot\..\..\BATCRelayBot\Private\Get-BotProcess.ps1" -Raw
        $source | Should -Match "pythonw\.exe"
    }

    It "does not rely on Get-Process for the command line" {
        # Get-Process objects have no CommandLine property on PowerShell 5.1,
        # which is what made the old detection match nothing at all. The
        # comments in that file quote the broken call deliberately, so only
        # executable lines are examined here.
        $source = Get-Content "$PSScriptRoot\..\..\BATCRelayBot\Private\Get-BotProcess.ps1" -Raw
        $code = [regex]::Replace($source, '<#.*?#>', '', 'Singleline')   # block comments
        $code = ($code -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"

        $code | Should -Match 'Win32_Process'
        $code | Should -Not -Match 'Get-Process\s+python'
    }
}

Describe "Uninstaller honesty" {

    It "no longer claims SDelete, which was never bundled" {
        $files = Get-ChildItem "$PSScriptRoot\..\..\BATCRelayBot" -Recurse -Filter *.ps1
        foreach ($file in $files) {
            (Get-Content $file.FullName -Raw) | Should -Not -Match 'SDelete' `
                -Because "$($file.Name) should not promise a tool the module does not ship"
        }
    }

    It "tells the user to reset the token, which is the only reliable step" {
        $summary = Get-Content "$PSScriptRoot\..\..\BATCRelayBot\Private\Show-PostRemovalSummary.ps1" -Raw
        $summary | Should -Match 'Reset Token'
    }

    It "does not shadow the automatic \$error variable" {
        $summary = Get-Content "$PSScriptRoot\..\..\BATCRelayBot\Private\Show-PostRemovalSummary.ps1" -Raw
        $summary | Should -Not -Match 'foreach\s*\(\s*\$error\s+in'
    }
}
