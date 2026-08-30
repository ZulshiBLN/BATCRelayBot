#Requires -Version 5.1

<#
.SYNOPSIS
Multi-level prerequisite detection functions for installer

.DESCRIPTION
Detect Python, ffmpeg, VoiceMeeter, and BeyondATC using progressive detection:
1. PATH environment variable (fastest)
2. Registry (for old installations)
3. Common filesystem paths (fallback)

Returns hashtable with Found, Path, Version, Method
#>

function Find-Python {
    [OutputType([hashtable])]
    param()

    # Level 1: Check PATH (fastest)
    try {
        $pythonExe = (Get-Command python.exe -ErrorAction Stop).Source
        $version = & $pythonExe --version 2>&1
        return @{
            Found = $true
            Path = $pythonExe
            Version = $version
            Method = "PATH"
        }
    } catch {}

    # Level 2: Check Registry (Python.org installations)
    try {
        $pythonReg = Get-ChildItem "HKCU:\Software\Python\PythonCore" -ErrorAction Stop |
                     Get-ItemProperty -ErrorAction SilentlyContinue |
                     Where-Object {$_.InstallPath} |
                     Select-Object -First 1

        if ($pythonReg -and (Test-Path "$($pythonReg.InstallPath)python.exe")) {
            return @{
                Found = $true
                Path = "$($pythonReg.InstallPath)python.exe"
                Version = "Unknown (Registry)"
                Method = "Registry"
            }
        }
    } catch {}

    # Level 3: Check Common Filesystem Paths
    $commonPaths = @(
        "C:\Program Files\Python*\python.exe",
        "C:\Program Files (x86)\Python*\python.exe",
        "$env:USERPROFILE\AppData\Local\Programs\Python\Python*\python.exe",
        "$env:USERPROFILE\AppData\Local\Microsoft\WindowsApps\python.exe"
    )

    foreach ($pattern in $commonPaths) {
        $found = Get-Item -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            return @{
                Found = $true
                Path = $found.FullName
                Version = "Unknown (FileSystem)"
                Method = "FileSystem"
            }
        }
    }

    # Not found
    return @{
        Found = $false
        Path = $null
        Version = $null
        Method = $null
    }
}

function Find-FFmpeg {
    [OutputType([hashtable])]
    param()

    # Level 1: Check PATH
    try {
        $ffmpegExe = (Get-Command ffmpeg.exe -ErrorAction Stop).Source
        $version = & $ffmpegExe -version 2>&1 | Select-Object -First 1
        return @{
            Found = $true
            Path = $ffmpegExe
            Version = $version
            Method = "PATH"
        }
    } catch {}

    # Level 2: Check Registry (Gyan.FFmpeg or similar winget installations)
    try {
        $ffmpegReg = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction Stop |
                     Get-ItemProperty -ErrorAction SilentlyContinue |
                     Where-Object {$_.DisplayName -match "FFmpeg"} |
                     Select-Object -First 1

        if ($ffmpegReg -and $ffmpegReg.InstallLocation) {
            $ffmpegExe = Join-Path $ffmpegReg.InstallLocation "bin\ffmpeg.exe"
            if (Test-Path $ffmpegExe) {
                return @{
                    Found = $true
                    Path = $ffmpegExe
                    Version = $ffmpegReg.DisplayVersion
                    Method = "Registry"
                }
            }
        }
    } catch {}

    # Level 3: Common Paths
    $commonPaths = @(
        "C:\Program Files\FFmpeg\bin\ffmpeg.exe",
        "C:\Program Files (x86)\FFmpeg\bin\ffmpeg.exe",
        "$env:USERPROFILE\AppData\Local\Programs\FFmpeg\bin\ffmpeg.exe",
        "C:\ffmpeg\bin\ffmpeg.exe"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            return @{
                Found = $true
                Path = $path
                Version = "Unknown (FileSystem)"
                Method = "FileSystem"
            }
        }
    }

    return @{
        Found = $false
        Path = $null
        Version = $null
        Method = $null
    }
}

function Find-VoiceMeeter {
    [OutputType([hashtable])]
    param()

    # Level 1: Registry - Search for any VoiceMeeter installation (flexible GUID matching)
    try {
        $vmReg = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction Stop |
                 Get-ItemProperty -ErrorAction SilentlyContinue |
                 Where-Object {$_.DisplayName -match "Voicemeeter"} |
                 Select-Object -First 1

        if ($vmReg -and $vmReg.InstallLocation -and (Test-Path $vmReg.InstallLocation)) {
            return @{
                Found = $true
                Path = $vmReg.InstallLocation
                Version = $vmReg.DisplayVersion
                Method = "Registry"
            }
        }
    } catch {}

    # Level 2: Check common filesystem paths (including variations)
    $commonPaths = @(
        "C:\Program Files\VB-Audio\Voicemeeter",
        "C:\Program Files (x86)\VB-Audio\Voicemeeter",
        "C:\Program Files\VB\Voicemeeter",
        "C:\Program Files (x86)\VB\Voicemeeter",
        "$env:PROGRAMFILES\VB-Audio\Voicemeeter",
        "$env:PROGRAMFILES(x86)\VB-Audio\Voicemeeter"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            return @{
                Found = $true
                Path = $path
                Version = "Unknown (FileSystem)"
                Method = "FileSystem"
            }
        }
    }

    return @{
        Found = $false
        Path = $null
        Version = $null
        Method = $null
    }
}

function Find-BeyondATC {
    [OutputType([hashtable])]
    param()

    # Level 1: Registry (most common installation method)
    try {
        $btcReg = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction Stop |
                  Get-ItemProperty -ErrorAction SilentlyContinue |
                  Where-Object {$_.DisplayName -match "BeyondATC"} |
                  Select-Object -First 1

        if ($btcReg -and $btcReg.InstallLocation) {
            return @{
                Found = $true
                Path = $btcReg.InstallLocation
                Version = $btcReg.DisplayVersion
                Method = "Registry"
            }
        }
    } catch {}

    # Level 2: Check common filesystem paths
    $commonPaths = @(
        "C:\Program Files\BeyondATC",
        "C:\Program Files (x86)\BeyondATC",
        "$env:USERPROFILE\AppData\Local\Programs\BeyondATC",
        "$env:LOCALAPPDATA\BeyondATC"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            return @{
                Found = $true
                Path = $path
                Version = "Unknown (FileSystem)"
                Method = "FileSystem"
            }
        }
    }

    return @{
        Found = $false
        Path = $null
        Version = $null
        Method = $null
    }
}

Export-ModuleMember -Function @(
    'Find-Python',
    'Find-FFmpeg',
    'Find-VoiceMeeter',
    'Find-BeyondATC'
)
