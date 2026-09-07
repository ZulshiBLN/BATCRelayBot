#Requires -Version 5.1

<#
.SYNOPSIS
Prerequisite detection for the installer.

.DESCRIPTION
Every detector returns a hashtable with at least:

    Found, Path, Version, Method, Reason

VoiceMeeter and BeyondATC additionally return ExePath and ProcessName,
because Start-BATCRelayBot launches them by executable and watches them by
process name.

Design rule: a candidate only counts as found once it has been *verified*.
Earlier versions trusted the first path that existed, which is how the
Windows Store stub at %LOCALAPPDATA%\Microsoft\WindowsApps\python.exe - a
zero-byte launcher that opens the Store instead of running Python - was
reported as a working interpreter, and how a manually installed Python
registered only under HKLM was missed entirely.
#>

$script:MinPythonMajor = 3
$script:MinPythonMinor = 10

function Test-PythonCandidate {
    <#
    .SYNOPSIS
    Verifies that a path is a real, new-enough Python interpreter.

    .OUTPUTS
    Hashtable with Ok, Version, Reason. Never throws.
    #>
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return @{ Ok = $false; Version = $null; Reason = "no path" }
    }
    if (-not (Test-Path $Path)) {
        return @{ Ok = $false; Version = $null; Reason = "path does not exist" }
    }

    # Microsoft Store app-execution aliases are zero-byte reparse points.
    # Executing one opens the Store and blocks, so filter by path *before*
    # running anything.
    if ($Path -like "*\WindowsApps\*") {
        return @{ Ok = $false; Version = $null; Reason = "Windows Store alias, not a real interpreter" }
    }
    try {
        if ((Get-Item $Path -ErrorAction Stop).Length -eq 0) {
            return @{ Ok = $false; Version = $null; Reason = "zero-byte stub" }
        }
    } catch {
        return @{ Ok = $false; Version = $null; Reason = "path not readable" }
    }

    try {
        $output = & $Path --version 2>&1 | Select-Object -First 1
    } catch {
        return @{ Ok = $false; Version = $null; Reason = "interpreter could not be executed" }
    }

    $text = "$output"
    if ($text -notmatch 'Python\s+(\d+)\.(\d+)(\.(\d+))?') {
        return @{ Ok = $false; Version = $null; Reason = "did not report a Python version" }
    }

    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]

    if ($major -lt $script:MinPythonMajor -or
        ($major -eq $script:MinPythonMajor -and $minor -lt $script:MinPythonMinor)) {
        return @{
            Ok      = $false
            Version = $text.Trim()
            Reason  = "Python $major.$minor found, but $($script:MinPythonMajor).$($script:MinPythonMinor)+ is required"
        }
    }

    return @{ Ok = $true; Version = $text.Trim(); Reason = $null }
}

function Get-PythonCandidatePath {
    <#
    .SYNOPSIS
    Yields every plausible python.exe location, best-known first.

    .DESCRIPTION
    Ordered so that a deliberately installed interpreter wins over whatever
    happens to sit on PATH.
    #>
    [OutputType([string[]])]
    param()

    $candidates = New-Object System.Collections.Generic.List[string]

    function Add-Candidate {
        param([string]$Value)
        if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $candidates.Contains($Value)) {
            $candidates.Add($Value)
        }
    }

    # 1. Per-user installs: the default for both python.org and winget.
    foreach ($root in @("$env:LOCALAPPDATA\Programs\Python", "$env:APPDATA\Python")) {
        try {
            Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object { Add-Candidate (Join-Path $_.FullName "python.exe") }
        } catch {}
    }

    # 2. Machine-wide installs ("Install for all users").
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $root) { continue }
        try {
            Get-ChildItem -Path $root -Directory -Filter "Python*" -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object { Add-Candidate (Join-Path $_.FullName "python.exe") }
        } catch {}
    }

    # 3. Registry. HKLM matters as much as HKCU: an all-users install writes
    #    only to HKLM, which pre-1.4.0 never looked at.
    foreach ($hive in @("HKLM:\Software\Python\PythonCore",
                        "HKLM:\Software\Wow6432Node\Python\PythonCore",
                        "HKCU:\Software\Python\PythonCore")) {
        try {
            Get-ChildItem $hive -ErrorAction Stop |
                Sort-Object PSChildName -Descending |
                ForEach-Object {
                    $installPath = (Get-ItemProperty "$($_.PSPath)\InstallPath" -ErrorAction SilentlyContinue).'(default)'
                    if ($installPath) { Add-Candidate (Join-Path $installPath "python.exe") }
                }
        } catch {}
    }

    # 4. The py launcher knows about interpreters in non-standard locations.
    try {
        $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
        if ($launcher) {
            & $launcher.Source -0p 2>&1 | ForEach-Object {
                if ("$_" -match '([A-Za-z]:\\[^\s].*python\.exe)') { Add-Candidate $Matches[1] }
            }
        }
    } catch {}

    # 5. PATH, last: most likely to be the Store alias.
    try {
        Get-Command python.exe -All -ErrorAction SilentlyContinue |
            ForEach-Object { Add-Candidate $_.Source }
    } catch {}

    return $candidates.ToArray()
}

function Find-Python {
    [OutputType([hashtable])]
    param()

    $rejected = $null

    foreach ($candidate in (Get-PythonCandidatePath)) {
        $check = Test-PythonCandidate -Path $candidate
        if ($check.Ok) {
            return @{
                Found   = $true
                Path    = $candidate
                Version = $check.Version
                Method  = "Verified ($candidate)"
                Reason  = $null
            }
        }
        # Remember a real-but-too-old interpreter so the user gets told why
        # their existing Python was not accepted.
        if (-not $rejected -and $check.Version) { $rejected = $check }
    }

    return @{
        Found   = $false
        Path    = $null
        Version = $rejected.Version
        Method  = $null
        Reason  = if ($rejected) { $rejected.Reason } else { "no Python interpreter found" }
    }
}

function Test-FFmpegCandidate {
    <#
    .SYNOPSIS
    Verifies that a path is a runnable ffmpeg binary.
    #>
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        return @{ Ok = $false; Version = $null }
    }
    if ($Path -like "*\WindowsApps\*") {
        return @{ Ok = $false; Version = $null }
    }

    try {
        $output = & $Path -version 2>&1 | Select-Object -First 1
    } catch {
        return @{ Ok = $false; Version = $null }
    }

    if ("$output" -match 'ffmpeg version\s+(\S+)') {
        return @{ Ok = $true; Version = $Matches[1] }
    }
    return @{ Ok = $false; Version = $null }
}

function Get-FFmpegCandidatePath {
    [OutputType([string[]])]
    param()

    $candidates = New-Object System.Collections.Generic.List[string]

    function Add-Candidate {
        param([string]$Value)
        if (-not [string]::IsNullOrWhiteSpace($Value) -and -not $candidates.Contains($Value)) {
            $candidates.Add($Value)
        }
    }

    # winget unpacks into a nested, version-named directory under AppData.
    foreach ($pattern in @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\*FFmpeg*\*\bin\ffmpeg.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\*FFmpeg*\bin\ffmpeg.exe",
        "$env:ProgramFiles\WinGet\Packages\*FFmpeg*\*\bin\ffmpeg.exe"
    )) {
        try {
            Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                ForEach-Object { Add-Candidate $_.FullName }
        } catch {}
    }

    # Registry entries from installer-based builds.
    foreach ($hive in @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
                        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
                        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall")) {
        try {
            Get-ChildItem $hive -ErrorAction Stop |
                Get-ItemProperty -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like "*FFmpeg*" -and $_.InstallLocation } |
                ForEach-Object {
                    Add-Candidate (Join-Path $_.InstallLocation "bin\ffmpeg.exe")
                    Add-Candidate (Join-Path $_.InstallLocation "ffmpeg.exe")
                }
        } catch {}
    }

    # Conventional manual-extraction locations.
    foreach ($path in @(
        "$env:ProgramFiles\FFmpeg\bin\ffmpeg.exe",
        "${env:ProgramFiles(x86)}\FFmpeg\bin\ffmpeg.exe",
        "$env:LOCALAPPDATA\Programs\FFmpeg\bin\ffmpeg.exe",
        "C:\ffmpeg\bin\ffmpeg.exe"
    )) {
        Add-Candidate $path
    }

    try {
        Get-Command ffmpeg.exe -All -ErrorAction SilentlyContinue |
            ForEach-Object { Add-Candidate $_.Source }
    } catch {}

    return $candidates.ToArray()
}

function Find-FFmpeg {
    [OutputType([hashtable])]
    param()

    foreach ($candidate in (Get-FFmpegCandidatePath)) {
        $check = Test-FFmpegCandidate -Path $candidate
        if ($check.Ok) {
            return @{
                Found   = $true
                Path    = $candidate
                Version = $check.Version
                Method  = "Verified ($candidate)"
                Reason  = $null
            }
        }
    }

    return @{
        Found   = $false
        Path    = $null
        Version = $null
        Method  = $null
        Reason  = "no runnable ffmpeg.exe found"
    }
}

function Resolve-VoiceMeeterExecutable {
    <#
    .SYNOPSIS
    Picks which VoiceMeeter executable Start-BATCRelayBot should launch.

    .DESCRIPTION
    A running instance is the most reliable signal: at install time
    VoiceMeeter is usually running, because its virtual devices only appear
    in ffmpeg's device list while it is. Otherwise fall back to the highest
    edition present, preferring 64-bit - the VB installers place every UI
    they ship into the same directory, so "highest present" identifies the
    edition the user actually installed.
    #>
    [OutputType([hashtable])]
    param([string]$InstallDirectory)

    $knownProcesses = @(
        'voicemeeter8x64', 'voicemeeter8',
        'voicemeeterpro_x64', 'voicemeeterpro',
        'voicemeeter_x64', 'voicemeeter'
    )

    foreach ($name in $knownProcesses) {
        try {
            $proc = Get-Process -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($proc -and $proc.Path) {
                return @{ ExePath = $proc.Path; ProcessName = $name }
            }
        } catch {}
    }

    if ([string]::IsNullOrWhiteSpace($InstallDirectory) -or -not (Test-Path $InstallDirectory)) {
        return @{ ExePath = $null; ProcessName = $null }
    }

    foreach ($name in $knownProcesses) {
        $exe = Join-Path $InstallDirectory "$name.exe"
        if (Test-Path $exe) {
            return @{ ExePath = $exe; ProcessName = $name }
        }
    }

    return @{ ExePath = $null; ProcessName = $null }
}

function Find-VoiceMeeter {
    [OutputType([hashtable])]
    param()

    $installDir = $null
    $version = "Unknown"
    $method = $null

    # Registry across all three hives that VB installers write to.
    foreach ($hive in @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
                        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
                        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall")) {
        if ($installDir) { break }
        try {
            $entry = Get-ChildItem $hive -ErrorAction Stop |
                Get-ItemProperty -ErrorAction SilentlyContinue |
                Where-Object {
                    ($_.DisplayName -like "*Voicemeeter*" -or $_.DisplayName -like "*VB-Audio*") -and
                    $_.InstallLocation -and (Test-Path $_.InstallLocation)
                } | Select-Object -First 1

            if ($entry) {
                $installDir = $entry.InstallLocation
                $version = if ($entry.DisplayVersion) { $entry.DisplayVersion } else { "Unknown" }
                $method = "Registry"
            }
        } catch {}
    }

    # Official install locations. VB uses "VB\", not "VB-Audio\", and
    # ${env:ProgramFiles(x86)} needs braces because of the parentheses.
    if (-not $installDir) {
        foreach ($path in @(
            "${env:ProgramFiles(x86)}\VB\Voicemeeter",
            "$env:ProgramFiles\VB\Voicemeeter",
            "$env:ProgramFiles\VB\VBVoicemeeterVAIOs"
        )) {
            if ($path -and (Test-Path $path)) {
                $installDir = $path
                $method = "FileSystem"
                break
            }
        }
    }

    # A running instance locates a portable or non-standard install.
    $resolved = Resolve-VoiceMeeterExecutable -InstallDirectory $installDir
    if (-not $installDir -and $resolved.ExePath) {
        $installDir = Split-Path -Parent $resolved.ExePath
        $method = "Running process"
    }

    if (-not $installDir) {
        return @{
            Found = $false; Path = $null; ExePath = $null; ProcessName = $null
            Version = $null; Method = $null; Reason = "VoiceMeeter is not installed"
        }
    }

    if (-not $resolved.ExePath) {
        # Directory present but no known executable in it - treat as not
        # usable rather than reporting a success the launcher cannot act on.
        return @{
            Found = $false; Path = $installDir; ExePath = $null; ProcessName = $null
            Version = $version; Method = $method
            Reason  = "VoiceMeeter directory found at $installDir, but no VoiceMeeter executable in it"
        }
    }

    return @{
        Found       = $true
        Path        = $installDir
        ExePath     = $resolved.ExePath
        ProcessName = $resolved.ProcessName
        Version     = $version
        Method      = $method
        Reason      = $null
    }
}

function Find-BeyondATC {
    [OutputType([hashtable])]
    param()

    $exePath = $null
    $installDir = $null
    $version = "Unknown"
    $method = $null

    try {
        $proc = Get-Process -Name "BeyondATC" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc -and $proc.Path) {
            $exePath = $proc.Path
            $installDir = Split-Path -Parent $exePath
            $method = "Running process"
        }
    } catch {}

    if (-not $exePath) {
        foreach ($hive in @("HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
                            "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
                            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall")) {
            if ($exePath) { break }
            try {
                $entry = Get-ChildItem $hive -ErrorAction Stop |
                    Get-ItemProperty -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -like "*BeyondATC*" -and $_.InstallLocation } |
                    Select-Object -First 1

                if ($entry) {
                    $candidate = Join-Path $entry.InstallLocation "BeyondATC.exe"
                    if (Test-Path $candidate) {
                        $exePath = $candidate
                        $installDir = $entry.InstallLocation
                        $version = if ($entry.DisplayVersion) { $entry.DisplayVersion } else { "Unknown" }
                        $method = "Registry"
                    }
                }
            } catch {}
        }
    }

    if (-not $exePath) {
        foreach ($dir in @("$env:ProgramFiles\BeyondATC", "${env:ProgramFiles(x86)}\BeyondATC")) {
            if (-not $dir) { continue }
            $candidate = Join-Path $dir "BeyondATC.exe"
            if (Test-Path $candidate) {
                $exePath = $candidate
                $installDir = $dir
                $method = "FileSystem"
                break
            }
        }
    }

    if ($exePath) {
        return @{
            Found = $true; Path = $installDir; ExePath = $exePath; ProcessName = "BeyondATC"
            Version = $version; Method = $method; Reason = $null
        }
    }

    # The LocalLow config folder proves BeyondATC has run on this machine but
    # says nothing about where the executable lives.
    $localLow = "$env:USERPROFILE\AppData\LocalLow\Skirmish Mode Games, Inc\BeyondATC"
    if (Test-Path $localLow) {
        return @{
            Found = $true; Path = $localLow; ExePath = $null; ProcessName = "BeyondATC"
            Version = "Unknown"; Method = "FileSystem (AppData LocalLow)"
            Reason  = "configuration found, but BeyondATC.exe could not be located"
        }
    }

    return @{
        Found = $false; Path = $null; ExePath = $null; ProcessName = $null
        Version = $null; Method = $null; Reason = "BeyondATC is not installed (optional)"
    }
}

Export-ModuleMember -Function @(
    'Find-Python',
    'Find-FFmpeg',
    'Find-VoiceMeeter',
    'Find-BeyondATC',
    'Test-PythonCandidate',
    'Test-FFmpegCandidate',
    'Resolve-VoiceMeeterExecutable'
)
