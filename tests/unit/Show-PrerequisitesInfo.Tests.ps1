# Phase 2 of the installer reports state and nothing else. It used to print a
# download link under every required component, which phase 3 then printed
# again beside whatever was actually missing.
#
# The tests here used to assert "-Not -Throw" five times over, once with
# "$true | Should -Be $true" beneath it. None of them could see the output, so
# none of them could notice any of this.
#
# Fixtures rather than the real machine: what these assert must hold whether or
# not the tester happens to have VoiceMeeter installed.

BeforeAll {
    # The .psm1 rather than the manifest: each private file exports itself and
    # the calls accumulate, so importing the module file reaches this function.
    # The manifest exports only the six public commands.
    Import-Module "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1" -Force

    $Complete = @{
        Python      = @{ Found = $true;  Path = 'C:\Py\python.exe'; Version = 'Python 3.12.10'; Method = 'Verified' }
        FFmpeg      = @{ Found = $true;  Path = 'C:\FF\ffmpeg.exe'; Version = '9.0.1';         Method = 'Verified' }
        VoiceMeeter = @{ Found = $true;  Path = 'C:\VB\Voicemeeter'; Version = '1.1.2.2';      Method = 'FileSystem' }
        BeyondATC   = @{ Found = $false; Path = $null; Version = $null; Method = $null
                         Reason = 'BeyondATC is not installed (optional)' }
    }

    $MissingPython = @{
        Python      = @{ Found = $false; Path = $null; Version = $null; Method = $null
                         Reason = 'no Python interpreter found' }
        FFmpeg      = @{ Found = $true;  Path = 'C:\FF\ffmpeg.exe'; Version = '9.0.1'; Method = 'Verified' }
        VoiceMeeter = @{ Found = $true;  Path = 'C:\VB\Voicemeeter'; Version = '1.1.2.2'; Method = 'FileSystem' }
        BeyondATC   = @{ Found = $false; Path = $null; Version = $null; Method = $null
                         Reason = 'BeyondATC is not installed (optional)' }
    }

    # Write-Host writes to the information stream; 2>&1 would capture nothing.
    function Get-Table {
        param([hashtable]$Prerequisites)
        ((Show-PrerequisitesInfo -Prerequisites $Prerequisites 6>&1) |
            ForEach-Object { "$_" }) -join "`n"
    }
}

Describe "Show-PrerequisitesInfo" {

    It "writes nothing to the success stream" {
        @(Show-PrerequisitesInfo -Prerequisites $Complete 6>$null).Count | Should -Be 0
    }

    It "prints no download links - phase 3 owns those" {
        $table = Get-Table -Prerequisites $MissingPython
        $table | Should -Not -Match 'https?://'
        $table | Should -Not -Match 'winget install'
    }

    It "shows the version beside FOUND, VoiceMeeter included" {
        $table = Get-Table -Prerequisites $Complete
        $table | Should -Match 'Python\s+FOUND \(Python 3\.12\.10\)'
        $table | Should -Match 'VoiceMeeter\s+FOUND \(1\.1\.2\.2\)'
    }

    It "says why a required component is missing" {
        Get-Table -Prerequisites $MissingPython | Should -Match 'no Python interpreter found'
    }

    # An optional component's reason repeated its status word for word:
    # "not installed (optional)" printed under "not installed (optional)".
    It "does not repeat itself for an optional component" {
        $lines = (Get-Table -Prerequisites $Complete) -split "`n" |
                 ForEach-Object { $_.Trim() } |
                 Where-Object { $_ -match 'optional' }

        $lines.Count | Should -Be 1
    }

    It "does not prompt" {
        $source = Get-Content "$PSScriptRoot\..\..\BATCRelayBot\Private\Show-PrerequisitesInfo.ps1" -Raw
        $source | Should -Not -Match 'Read-Host'
    }
}

Describe "Detection results share one shape" {
    # Show-PrerequisitesInfo reads Found, Path, Version and Reason off whatever
    # the Find-* functions return, so they have to agree on the field names.
    It "every Find-* function returns the fields the display reads" {
        foreach ($result in @((Find-Python), (Find-FFmpeg), (Find-VoiceMeeter), (Find-BeyondATC))) {
            $result.Keys | Should -Contain "Found"
            $result.Keys | Should -Contain "Path"
            $result.Keys | Should -Contain "Version"
            $result.Keys | Should -Contain "Method"
        }
    }
}
