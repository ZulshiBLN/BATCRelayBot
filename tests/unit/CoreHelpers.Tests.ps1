#Requires -Version 5.1

<#
.SYNOPSIS
Tests for helpers whose silent failure has real consequences.

.DESCRIPTION
These functions carry no user interface, so nothing visible breaks when they
stop working correctly - the token simply appears in a log, or a working
Python is reported as missing. That makes them exactly the ones worth pinning
down.
#>

BeforeAll {
    Import-Module "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1" -Force

    $script:SandboxRoot = Join-Path ([System.IO.Path]::GetTempPath()) "batc-helper-tests"

    function New-HelperSandbox {
        $path = Join-Path $script:SandboxRoot ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        return $path
    }
}

AfterAll {
    if ($script:SandboxRoot -and (Test-Path $script:SandboxRoot)) {
        Remove-Item $script:SandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Remove-SensitiveData" {

    # Everything written to install.log passes through here. A regression is
    # invisible until someone pastes a log into an issue.
    BeforeAll {
        $script:Token = ("A" * 24) + "." + ("Bc1De2") + "." + ("X" * 27)
    }

    It "redacts a bot token appearing on its own" {
        $result = Remove-SensitiveData -Text "Using token $script:Token now"
        $result | Should -Not -Match ([regex]::Escape($script:Token))
        $result | Should -Match 'REDACTED'
    }

    It "redacts a token behind an Authorization header" {
        $result = Remove-SensitiveData -Text "Authorization: Bot $script:Token"
        $result | Should -Not -Match ([regex]::Escape($script:Token))
    }

    It "redacts every occurrence, not just the first" {
        $result = Remove-SensitiveData -Text "$script:Token and again $script:Token"
        $result | Should -Not -Match ([regex]::Escape($script:Token))
    }

    It "leaves ordinary text alone" {
        $text = "Installed Python 3.12.10 at C:\Python312\python.exe"
        Remove-SensitiveData -Text $text | Should -Be $text
    }

    It "does not mangle a file path that merely contains dots" {
        $text = "C:\Users\someone\AppData\Local\Programs\Python\Python312\python.exe"
        Remove-SensitiveData -Text $text | Should -Be $text
    }

    It "handles empty and null input without throwing" {
        { Remove-SensitiveData -Text "" } | Should -Not -Throw
        { Remove-SensitiveData -Text $null } | Should -Not -Throw
    }
}

Describe "Test-PythonCandidate" {

    It "rejects a path that does not exist" {
        (Test-PythonCandidate -Path "C:\definitely\not\here\python.exe").Ok | Should -BeFalse
    }

    It "rejects an empty path" {
        (Test-PythonCandidate -Path "").Ok | Should -BeFalse
    }

    It "rejects the Windows Store alias without executing it" {
        # A zero-byte reparse point that opens the Store. Running it blocks,
        # so it has to be filtered by path first.
        $result = Test-PythonCandidate -Path "C:\Users\x\AppData\Local\Microsoft\WindowsApps\python.exe"
        $result.Ok     | Should -BeFalse
        $result.Reason | Should -Match 'Store'
    }

    It "rejects a zero-byte file" {
        $sandbox = New-HelperSandbox
        $stub = Join-Path $sandbox "python.exe"
        New-Item -ItemType File -Path $stub -Force | Out-Null

        $result = Test-PythonCandidate -Path $stub
        $result.Ok     | Should -BeFalse
        $result.Reason | Should -Match 'zero-byte'
    }

    It "rejects something that runs but is not Python" {
        $sandbox = New-HelperSandbox
        $fake = Join-Path $sandbox "python.cmd"
        Set-Content -Path $fake -Value "@echo off`r`necho not an interpreter" -Encoding ASCII

        (Test-PythonCandidate -Path $fake).Ok | Should -BeFalse
    }

    It "rejects an interpreter older than 3.10 but reports its version" {
        $sandbox = New-HelperSandbox
        $old = Join-Path $sandbox "python.cmd"
        Set-Content -Path $old -Value "@echo off`r`necho Python 3.8.10" -Encoding ASCII

        $result = Test-PythonCandidate -Path $old
        $result.Ok      | Should -BeFalse
        $result.Version | Should -Match '3\.8'
        $result.Reason  | Should -Match '3\.10'
    }

    It "accepts a new-enough interpreter" {
        $sandbox = New-HelperSandbox
        $good = Join-Path $sandbox "python.cmd"
        Set-Content -Path $good -Value "@echo off`r`necho Python 3.12.10" -Encoding ASCII

        $result = Test-PythonCandidate -Path $good
        $result.Ok      | Should -BeTrue
        $result.Version | Should -Match '3\.12\.10'
    }
}

Describe "Test-FFmpegCandidate" {

    It "rejects a missing path" {
        (Test-FFmpegCandidate -Path "C:\nope\ffmpeg.exe").Ok | Should -BeFalse
    }

    It "accepts a binary that reports an ffmpeg version" {
        $sandbox = New-HelperSandbox
        $fake = Join-Path $sandbox "ffmpeg.cmd"
        Set-Content -Path $fake -Value "@echo off`r`necho ffmpeg version 7.1-full_build" -Encoding ASCII

        $result = Test-FFmpegCandidate -Path $fake
        $result.Ok      | Should -BeTrue
        $result.Version | Should -Be '7.1-full_build'
    }

    It "rejects a binary that reports something else" {
        $sandbox = New-HelperSandbox
        $fake = Join-Path $sandbox "ffmpeg.cmd"
        Set-Content -Path $fake -Value "@echo off`r`necho some other tool" -Encoding ASCII

        (Test-FFmpegCandidate -Path $fake).Ok | Should -BeFalse
    }
}

Describe "Resolve-VoiceMeeterExecutable" {

    BeforeEach {
        # A running instance takes precedence by design - it identifies the
        # edition the user actually runs. Suppress it so the directory branch
        # is what these cases exercise; the machine running the suite may well
        # have VoiceMeeter open.
        Mock -ModuleName BATCRelayBot Get-Process { $null }
    }

    It "returns nothing for a directory that does not exist" {
        $result = Resolve-VoiceMeeterExecutable -InstallDirectory "C:\nope\VB\Voicemeeter"
        $result.ExePath | Should -BeNullOrEmpty
    }

    It "returns nothing when no directory is given" {
        (Resolve-VoiceMeeterExecutable -InstallDirectory "").ExePath | Should -BeNullOrEmpty
    }

    It "prefers the highest edition present" {
        # The VB installers drop every UI they ship into one directory, so the
        # highest edition present identifies what the user installed.
        $sandbox = New-HelperSandbox
        foreach ($exe in 'voicemeeter.exe', 'voicemeeter_x64.exe', 'voicemeeter8x64.exe') {
            Set-Content -Path (Join-Path $sandbox $exe) -Value "stub" -Encoding ASCII
        }

        $result = Resolve-VoiceMeeterExecutable -InstallDirectory $sandbox
        $result.ProcessName | Should -Be 'voicemeeter8x64'
    }

    It "falls back to the base edition when only that is installed" {
        $sandbox = New-HelperSandbox
        Set-Content -Path (Join-Path $sandbox 'voicemeeter_x64.exe') -Value "stub" -Encoding ASCII

        $result = Resolve-VoiceMeeterExecutable -InstallDirectory $sandbox
        $result.ProcessName | Should -Be 'voicemeeter_x64'
    }

    It "reports a process name Get-Process can use" {
        $sandbox = New-HelperSandbox
        Set-Content -Path (Join-Path $sandbox 'voicemeeter_x64.exe') -Value "stub" -Encoding ASCII

        (Resolve-VoiceMeeterExecutable -InstallDirectory $sandbox).ProcessName |
            Should -Not -Match '\.exe$'
    }

    It "prefers a running instance over the directory" {
        # Without the mock: whatever edition is actually running wins, because
        # that is the one Start-BATCRelayBot must not start a second copy of.
        $sandbox = New-HelperSandbox
        Set-Content -Path (Join-Path $sandbox 'voicemeeter.exe') -Value "stub" -Encoding ASCII

        Mock -ModuleName BATCRelayBot Get-Process {
            [PSCustomObject]@{ Path = 'C:\VB\Voicemeeter\voicemeeter8x64.exe' }
        } -ParameterFilter { $Name -eq 'voicemeeter8x64' }

        $result = Resolve-VoiceMeeterExecutable -InstallDirectory $sandbox
        $result.ProcessName | Should -Be 'voicemeeter8x64'
    }
}

Describe "ConvertTo-DiscordId" {

    It "converts a snowflake string to a number" {
        ConvertTo-DiscordId "123456789012345678" | Should -BeOfType [long]
    }

    It "keeps a number a number" {
        ConvertTo-DiscordId ([long]123456789012345678) | Should -Be 123456789012345678
    }

    It "leaves a non-numeric value untouched rather than guessing" {
        ConvertTo-DiscordId "not-an-id" | Should -Be "not-an-id"
    }

    It "returns null for null" {
        ConvertTo-DiscordId $null | Should -BeNullOrEmpty
    }
}

Describe "Get-ModuleVersion" {

    It "returns the manifest version, not 0.0" {
        # (Get-Module).Version reports 0.0 when the .psm1 was imported
        # directly, which is how the test suite loads it.
        $version = Get-ModuleVersion
        $version | Should -Not -Be '0.0'
        $version | Should -Match '^\d+\.\d+\.\d+$'
    }

    It "agrees with the manifest on disk" {
        $manifest = Import-PowerShellDataFile "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psd1"
        Get-ModuleVersion | Should -Be $manifest.ModuleVersion
    }
}

Describe "Initialize-InstallLog" {

    It "creates the directory and the log before anything can fail" {
        $sandbox = Join-Path (New-HelperSandbox) "not-yet-created"
        $logPath = Initialize-InstallLog -InstallPath $sandbox -Version "1.4.0"

        $logPath | Should -Not -BeNullOrEmpty
        Test-Path $logPath | Should -BeTrue
    }

    It "records the version and the environment in the header" {
        $sandbox = New-HelperSandbox
        $logPath = Initialize-InstallLog -InstallPath $sandbox -Version "1.4.0"
        $content = Get-Content $logPath -Raw

        $content | Should -Match '1\.4\.0'
        $content | Should -Match 'PowerShell'
    }

    It "appends a second session rather than truncating the first" {
        $sandbox = New-HelperSandbox
        Initialize-InstallLog -InstallPath $sandbox -Version "1.4.0" | Out-Null
        $logPath = Initialize-InstallLog -InstallPath $sandbox -Version "1.4.0"

        (Get-Content $logPath | Select-String 'session started').Count | Should -Be 2
    }
}

Describe "Write-InstallLog" {

    It "redacts a token on its way into the log" {
        $sandbox = New-HelperSandbox
        $logPath = Initialize-InstallLog -InstallPath $sandbox -Version "1.4.0"
        $token = ("Q" * 24) + ".Ab1Cd2." + ("Z" * 27)

        Write-InstallLog -Message "token is $token" -LogPath $logPath

        (Get-Content $logPath -Raw) | Should -Not -Match ([regex]::Escape($token))
    }

    It "never throws, whatever the path" {
        { Write-InstallLog -Message "x" -LogPath "" } | Should -Not -Throw
        { Write-InstallLog -Message "x" -LogPath $null } | Should -Not -Throw
        { Write-InstallLog -Message "x" -LogPath "Q:\nope\install.log" } | Should -Not -Throw
    }
}

Describe "ConvertFrom-SecureStringToPlainText" {

    It "round-trips a value" {
        $secure = ConvertTo-SecureString "hello-world" -AsPlainText -Force
        ConvertFrom-SecureStringToPlainText -Secure $secure | Should -Be "hello-world"
    }

    It "returns null for null input" {
        ConvertFrom-SecureStringToPlainText -Secure $null | Should -BeNullOrEmpty
    }
}

Describe "Protect-BotConfigFile" {

    It "removes inherited permissions from the file" {
        $sandbox = New-HelperSandbox
        $configPath = Join-Path $sandbox "config.json"
        '{"bot_token":"x"}' | Set-Content $configPath -Encoding UTF8

        Protect-BotConfigFile -ConfigPath $configPath | Out-Null

        (Get-Acl $configPath).AreAccessRulesProtected | Should -BeTrue
    }

    It "reports failure instead of throwing when the file is gone" {
        $absent = Join-Path (New-HelperSandbox) "missing.json"
        { Protect-BotConfigFile -ConfigPath $absent } | Should -Not -Throw
        Protect-BotConfigFile -ConfigPath $absent | Should -BeFalse
    }
}

Describe "Read-DiscordSnowflake" {

    It "accepts a well-formed ID" {
        Mock -ModuleName BATCRelayBot Read-Host { "123456789012345678" }
        Mock -ModuleName BATCRelayBot Write-InstallLog { }

        Read-DiscordSnowflake -Label "Server ID" -Hint "x" 6>$null |
            Should -Be "123456789012345678"
    }

    It "returns null when the user enters nothing" {
        Mock -ModuleName BATCRelayBot Read-Host { "" }
        Read-DiscordSnowflake -Label "Server ID" -Hint "x" 6>$null | Should -BeNullOrEmpty
    }

    It "trims surrounding whitespace" {
        Mock -ModuleName BATCRelayBot Read-Host { "  123456789012345678  " }
        Mock -ModuleName BATCRelayBot Write-InstallLog { }

        Read-DiscordSnowflake -Label "Server ID" -Hint "x" 6>$null |
            Should -Be "123456789012345678"
    }
}

Describe "Get-PythonCandidatePath" {

    # This list is where the search looks. A missing location is exactly how
    # an all-users Python went undetected before 1.4.0.
    BeforeAll { $script:PythonCandidates = @(Get-PythonCandidatePath) }

    It "returns candidates" {
        $script:PythonCandidates.Count | Should -BeGreaterThan 0
    }

    It "contains no duplicates" {
        ($script:PythonCandidates | Select-Object -Unique).Count |
            Should -Be $script:PythonCandidates.Count
    }

    It "covers the per-user location, the default for python.org and winget" {
        $source = Get-Content "$PSScriptRoot\..\..\BATCRelayBot\Private\Find-Prerequisites.ps1" -Raw
        $source | Should -Match ([regex]::Escape('LOCALAPPDATA\Programs\Python'))
    }

    It "covers HKLM, not only HKCU" {
        # An all-users install writes only to HKLM; searching HKCU alone is
        # what made a perfectly good Python invisible.
        $source = Get-Content "$PSScriptRoot\..\..\BATCRelayBot\Private\Find-Prerequisites.ps1" -Raw
        $source | Should -Match ([regex]::Escape('HKLM:\Software\Python\PythonCore'))
        $source | Should -Match ([regex]::Escape('HKCU:\Software\Python\PythonCore'))
    }

    It "consults the py launcher" {
        $source = Get-Content "$PSScriptRoot\..\..\BATCRelayBot\Private\Find-Prerequisites.ps1" -Raw
        $source | Should -Match 'py\.exe'
    }
}

Describe "Get-FFmpegCandidatePath" {

    BeforeAll { $script:FFmpegCandidates = @(Get-FFmpegCandidatePath) }

    It "returns candidates" {
        $script:FFmpegCandidates.Count | Should -BeGreaterThan 0
    }

    It "contains no duplicates" {
        ($script:FFmpegCandidates | Select-Object -Unique).Count |
            Should -Be $script:FFmpegCandidates.Count
    }

    It "covers winget's nested package directory" {
        # winget unpacks ffmpeg into a version-named subdirectory under
        # AppData - CL-18, and the reason auto-install looked like it failed.
        $source = Get-Content "$PSScriptRoot\..\..\BATCRelayBot\Private\Find-Prerequisites.ps1" -Raw
        $source | Should -Match ([regex]::Escape('WinGet\Packages\*FFmpeg*'))
    }
}

Describe "Stop-BotProcess" {

    It "reports 'not running' when nothing matches" {
        $absent = Join-Path ([System.IO.Path]::GetTempPath()) "batc-none-$([guid]::NewGuid())"
        $result = Stop-BotProcess -BotPath $absent -TimeoutSeconds 1

        $result.Stopped | Should -BeTrue
        $result.Method  | Should -Be 'not running'
    }

    It "prefers the stop signal over terminating the process" {
        # Force-killing a connected voice client leaves the bot visibly stuck
        # in the channel, so the graceful path must be tried first.
        $sandbox = New-HelperSandbox
        $script:FindCalls = 0

        Mock -ModuleName BATCRelayBot Find-BotProcess {
            $script:FindCalls++
            if ($script:FindCalls -eq 1) { return @(4242) }
            return @()
        }
        Mock -ModuleName BATCRelayBot Stop-Process { throw "must not be force-stopped" }

        $result = Stop-BotProcess -BotPath $sandbox -TimeoutSeconds 5

        $result.Stopped | Should -BeTrue
        $result.Method  | Should -Be 'graceful'
        Should -Invoke -ModuleName BATCRelayBot Stop-Process -Times 0
    }

    It "removes the stop signal it created" {
        $sandbox = New-HelperSandbox
        $script:FindCalls2 = 0
        Mock -ModuleName BATCRelayBot Find-BotProcess {
            $script:FindCalls2++
            if ($script:FindCalls2 -eq 1) { return @(4242) }
            return @()
        }

        Stop-BotProcess -BotPath $sandbox -TimeoutSeconds 5 | Out-Null

        Test-Path (Join-Path $sandbox "stop.signal") | Should -BeFalse
    }

    It "falls back to terminating when the signal is ignored" {
        $sandbox = New-HelperSandbox
        Mock -ModuleName BATCRelayBot Find-BotProcess { @(4242) }
        Mock -ModuleName BATCRelayBot Stop-Process { }

        $result = Stop-BotProcess -BotPath $sandbox -TimeoutSeconds 1

        $result.Method | Should -Be 'forced'
        Should -Invoke -ModuleName BATCRelayBot Stop-Process -Times 1
    }
}
