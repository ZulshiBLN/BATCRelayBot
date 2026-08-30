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

    # Level 1: Check winget default location (AppData) - HIGHEST PRIORITY
    try {
        $pythonExe = Get-ChildItem -Path "$env:LOCALAPPDATA\Programs\Python\*\python.exe" -ErrorAction SilentlyContinue |
                     Select-Object -First 1
        if ($pythonExe) {
            $version = & $pythonExe.FullName --version 2>&1
            return @{
                Found = $true
                Path = $pythonExe.FullName
                Version = $version
                Method = "FileSystem (winget/AppData)"
            }
        }
    } catch {}

    # Level 2: Check Program Files (machine-scope or manual installs)
    try {
        $pythonExe = Get-ChildItem -Path "C:\Program Files\Python*\python.exe" -ErrorAction SilentlyContinue |
                     Select-Object -First 1
        if ($pythonExe) {
            $version = & $pythonExe.FullName --version 2>&1
            return @{
                Found = $true
                Path = $pythonExe.FullName
                Version = $version
                Method = "FileSystem (Program Files)"
            }
        }
    } catch {}

    # Level 3: Check Registry (Python.org installations)
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

    # Level 4: Check PATH (fallback if PATH was updated)
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

    # Level 1: Check winget default location (AppData) - HIGHEST PRIORITY - NESTED DIRECTORY STRUCTURE
    try {
        $ffmpegExe = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Gyan.FFmpeg*\*\bin\ffmpeg.exe" -ErrorAction SilentlyContinue |
                     Select-Object -First 1
        if ($ffmpegExe) {
            $version = & $ffmpegExe.FullName -version 2>&1 | Select-Object -First 1
            return @{
                Found = $true
                Path = $ffmpegExe.FullName
                Version = $version
                Method = "FileSystem (winget/AppData)"
            }
        }
    } catch {}

    # Level 2: Check Program Files (machine-scope winget installs)
    try {
        $ffmpegExe = Get-ChildItem -Path "C:\Program Files\WinGet\Packages\Gyan.FFmpeg*\*\bin\ffmpeg.exe" -ErrorAction SilentlyContinue |
                     Select-Object -First 1
        if ($ffmpegExe) {
            $version = & $ffmpegExe.FullName -version 2>&1 | Select-Object -First 1
            return @{
                Found = $true
                Path = $ffmpegExe.FullName
                Version = $version
                Method = "FileSystem (Program Files/winget)"
            }
        }
    } catch {}

    # Level 3: Check Registry (Gyan.FFmpeg or similar installations)
    try {
        $ffmpegReg = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction Stop |
                     Get-ItemProperty -ErrorAction SilentlyContinue |
                     Where-Object {$_.DisplayName -like "*FFmpeg*"} |
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

    # Level 4: Check other common paths (manual/traditional installs)
    $commonPaths = @(
        "C:\Program Files\FFmpeg\bin\ffmpeg.exe",
        "C:\Program Files (x86)\FFmpeg\bin\ffmpeg.exe",
        "C:\ffmpeg\bin\ffmpeg.exe"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            return @{
                Found = $true
                Path = $path
                Version = "Unknown (FileSystem)"
                Method = "FileSystem (manual)"
            }
        }
    }

    # Level 5: Check PATH (fallback if PATH was updated)
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

    # Level 1: Registry (HKLM) - Search for VoiceMeeter with case-insensitive pattern
    try {
        $vmReg = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction Stop |
                 Get-ItemProperty -ErrorAction SilentlyContinue |
                 Where-Object {$_.DisplayName -like "*Voicemeeter*" -or $_.DisplayName -like "*VB-Audio*"} |
                 Select-Object -First 1

        if ($vmReg -and $vmReg.InstallLocation -and (Test-Path $vmReg.InstallLocation)) {
            return @{
                Found = $true
                Path = $vmReg.InstallLocation
                Version = $vmReg.DisplayVersion
                Method = "Registry (HKLM)"
            }
        }
    } catch {}

    # Level 1b: Registry (HKCU) - User-level installations
    try {
        $vmReg = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction Stop |
                 Get-ItemProperty -ErrorAction SilentlyContinue |
                 Where-Object {$_.DisplayName -like "*Voicemeeter*" -or $_.DisplayName -like "*VB-Audio*"} |
                 Select-Object -First 1

        if ($vmReg -and $vmReg.InstallLocation -and (Test-Path $vmReg.InstallLocation)) {
            return @{
                Found = $true
                Path = $vmReg.InstallLocation
                Version = $vmReg.DisplayVersion
                Method = "Registry (HKCU)"
            }
        }
    } catch {}

    # Level 1c: Registry (WOW6432Node) - 32-bit registry on 64-bit systems
    try {
        $vmReg = Get-ChildItem "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction Stop |
                 Get-ItemProperty -ErrorAction SilentlyContinue |
                 Where-Object {$_.DisplayName -like "*Voicemeeter*" -or $_.DisplayName -like "*VB-Audio*"} |
                 Select-Object -First 1

        if ($vmReg -and $vmReg.InstallLocation -and (Test-Path $vmReg.InstallLocation)) {
            return @{
                Found = $true
                Path = $vmReg.InstallLocation
                Version = $vmReg.DisplayVersion
                Method = "Registry (WOW6432)"
            }
        }
    } catch {}

    # Level 2: Check official VoiceMeeter installation paths
    # Official installations use "VB\" not "VB-Audio\"
    $commonPaths = @(
        "C:\Program Files (x86)\VB\Voicemeeter",      # 32-bit driver (primary)
        "C:\Program Files\VB\VBVoicemeeterVAIOs",    # 64-bit ASIO driver
        "C:\Program Files\VB\Voicemeeter",            # Alternative 64-bit location
        "$env:PROGRAMFILES(x86)\VB\Voicemeeter",      # 32-bit with env var
        "$env:PROGRAMFILES\VB\Voicemeeter",           # 64-bit with env var
        "$env:PROGRAMFILES\VB\VBVoicemeeterVAIOs"    # ASIO with env var
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

    # Level 3: Wildcard search for VB folder (catches portable/non-standard installations)
    try {
        $vbDirs = Get-ChildItem -Path "C:\Program Files", "C:\Program Files (x86)" -Directory -ErrorAction SilentlyContinue |
                  Where-Object {$_.Name -eq "VB"} |
                  Get-ChildItem -Directory -ErrorAction SilentlyContinue |
                  Where-Object {$_.Name -like "*Voicemeeter*" -or $_.Name -like "*VAIO*"} |
                  Select-Object -First 1

        if ($vbDirs -and (Test-Path $vbDirs.FullName)) {
            return @{
                Found = $true
                Path = $vbDirs.FullName
                Version = "Unknown (Wildcard Search)"
                Method = "FileSystem (Wildcard)"
            }
        }
    } catch {}

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
