#Requires -Version 5.1

function Start-Installation {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Prerequisites,
        [Parameter(Mandatory = $true)]
        [hashtable]$DiscordConfig
    )

    $installPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
    $logPath = Join-Path $installPath "install.log"

    Write-Host ""
    Write-Host "Starting Installation..." -ForegroundColor Green
    Write-Host ""

    # PHASE 0b: Migrate existing configuration (apply ACL security to existing configs)
    $existingConfigPath = Join-Path $installPath "config.json"
    if (Test-Path $existingConfigPath) {
        Write-Host "[0b/6] Securing existing configuration..." -ForegroundColor Cyan
        try {
            $acl = Get-Acl -Path $existingConfigPath
            $acl.SetAccessRuleProtection($true, $false)

            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            if ($currentUser) {
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $currentUser,
                    'FullControl',
                    'Allow'
                )
                $acl.SetAccessRule($rule)
                Set-Acl -Path $existingConfigPath -AclObject $acl -ErrorAction Stop
                Log-Message "MIGRATION: Applied ACL security to existing config.json" -LogPath $logPath
                Write-Host "      DONE - Configuration secured for v1.3.16" -ForegroundColor Green
            }
        } catch {
            Log-Message "MIGRATION-WARNING: Could not apply ACL to existing config: $_" -LogPath $logPath
            Write-Host "      WARNING: Existing config permissions unchanged (non-critical)" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    # Create installation directory
    Write-Host "[1/6] Creating installation directory..." -ForegroundColor Cyan
    try {
        if (-not (Test-Path $installPath)) {
            New-Item -ItemType Directory -Path $installPath -Force | Out-Null
            Log-Message "Created installation directory: $installPath" -LogPath $logPath
        }
        Write-Host "      DONE" -ForegroundColor Green
    } catch {
        Log-Message "ERROR: Could not create installation directory: $_" -LogPath $logPath
        Write-Host "      FAILED: $_" -ForegroundColor Red
        return @{ Success = $false; Error = "Directory creation failed" }
    }

    # Auto-install missing prerequisites
    Write-Host "[2/6] Ensuring required tools are installed..." -ForegroundColor Cyan
    try {
        if (-not $Prerequisites.Python.Found) {
            Write-Host "      Installing Python 3.12..." -ForegroundColor Gray
            winget install Python.Python.3.12 --silent 2>&1 | Out-Null

            if ($LASTEXITCODE -ne 0) {
                Log-Message "WARNING: Python installation returned exit code $LASTEXITCODE" -LogPath $logPath
                Write-Host "      WARNING: Python install failed" -ForegroundColor Yellow
            } else {
                Log-Message "Python.Python.3.12 install command completed" -LogPath $logPath
            }

            # Wait for installation to complete and registry to update
            Start-Sleep -Seconds 2

            # Refresh PowerShell PATH from system registry (winget updates system PATH only)
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','User')

            # Re-detect Python after installation
            $pythonCheck = & {
                # Level 1: Check winget default location (AppData)
                try {
                    $pythonDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Programs\Python\*\python.exe" -ErrorAction SilentlyContinue |
                                 Select-Object -First 1
                    if ($pythonDir) {
                        return @{Found = $true; Path = $pythonDir.FullName}
                    }
                } catch {}

                # Level 2: Check Program Files (for machine-scope or manual installs)
                try {
                    $pythonDir = Get-ChildItem -Path "C:\Program Files\Python*\python.exe" -ErrorAction SilentlyContinue |
                                 Select-Object -First 1
                    if ($pythonDir) {
                        return @{Found = $true; Path = $pythonDir.FullName}
                    }
                } catch {}

                # Level 3: Fallback to Get-Command (if PATH was updated)
                try {
                    $pythonExe = (Get-Command python.exe -ErrorAction Stop).Source
                    return @{Found = $true; Path = $pythonExe}
                } catch {
                    return @{Found = $false; Path = $null}
                }
            }
            if ($pythonCheck.Found) {
                $Prerequisites.Python = @{Found = $true; Path = $pythonCheck.Path}
                Log-Message "Python installed and detected: $($pythonCheck.Path)" -LogPath $logPath
            } else {
                Log-Message "ERROR: Python installation completed but executable not found in expected locations" -LogPath $logPath
                Write-Host "      ERROR: Python not detected after installation" -ForegroundColor Red
            }
        }

        if (-not $Prerequisites.FFmpeg.Found) {
            Write-Host "      Installing FFmpeg..." -ForegroundColor Gray
            winget install Gyan.FFmpeg --silent 2>&1 | Out-Null

            if ($LASTEXITCODE -ne 0) {
                Log-Message "WARNING: FFmpeg installation returned exit code $LASTEXITCODE" -LogPath $logPath
                Write-Host "      WARNING: FFmpeg install failed" -ForegroundColor Yellow
            } else {
                Log-Message "Gyan.FFmpeg install command completed" -LogPath $logPath
            }

            # Wait for installation to complete and registry to update
            Start-Sleep -Seconds 2

            # Refresh PowerShell PATH from system registry (winget updates system PATH only)
            $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('PATH','User')

            # Re-detect FFmpeg after installation
            $ffmpegCheck = & {
                # Level 1: Check winget default location (AppData) - has nested version directory
                try {
                    $ffmpegExe = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Gyan.FFmpeg*\*\bin\ffmpeg.exe" -ErrorAction SilentlyContinue |
                                 Select-Object -First 1
                    if ($ffmpegExe) {
                        return @{Found = $true; Path = $ffmpegExe.FullName}
                    }
                } catch {}

                # Level 2: Check Program Files (for machine-scope installs)
                try {
                    $ffmpegExe = Get-ChildItem -Path "C:\Program Files\WinGet\Packages\Gyan.FFmpeg*\*\bin\ffmpeg.exe" -ErrorAction SilentlyContinue |
                                 Select-Object -First 1
                    if ($ffmpegExe) {
                        return @{Found = $true; Path = $ffmpegExe.FullName}
                    }
                } catch {}

                # Level 3: Fallback to Get-Command (if PATH was updated)
                try {
                    $ffmpegExe = (Get-Command ffmpeg.exe -ErrorAction Stop).Source
                    return @{Found = $true; Path = $ffmpegExe}
                } catch {
                    return @{Found = $false; Path = $null}
                }
            }
            if ($ffmpegCheck.Found) {
                $Prerequisites.FFmpeg = @{Found = $true; Path = $ffmpegCheck.Path}
                Log-Message "FFmpeg installed and detected: $($ffmpegCheck.Path)" -LogPath $logPath
            } else {
                Log-Message "ERROR: FFmpeg installation completed but executable not found in expected locations" -LogPath $logPath
                Write-Host "      ERROR: FFmpeg not detected after installation" -ForegroundColor Red
            }
        }

        Write-Host "      DONE" -ForegroundColor Green
    } catch {
        Log-Message "WARNING: Auto-install of prerequisites had issues: $_" -LogPath $logPath
        Write-Host "      WARNING: $_" -ForegroundColor Yellow
    }

    # Install Python dependencies
    Write-Host "[3/6] Installing Python dependencies..." -ForegroundColor Cyan
    try {
        if ($Prerequisites.Python.Found) {
            $pythonPath = $Prerequisites.Python.Path
            $requirementsPath = Get-RequirementsPath

            if (Test-Path $requirementsPath) {
                & $pythonPath -m pip install -r $requirementsPath -q
                Log-Message "Python dependencies installed successfully" -LogPath $logPath
                Write-Host "      DONE" -ForegroundColor Green
            } else {
                Log-Message "WARNING: requirements.txt not found at $requirementsPath" -LogPath $logPath
                Write-Host "      SKIPPED (requirements.txt not found)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "      SKIPPED (Python not available)" -ForegroundColor Yellow
        }
    } catch {
        Log-Message "ERROR: Python dependency installation failed: $_" -LogPath $logPath
        Write-Host "      FAILED: $_" -ForegroundColor Red
        return @{ Success = $false; Error = "Dependency installation failed" }
    }

    # Create configuration file
    Write-Host "[4/6] Creating configuration file..." -ForegroundColor Cyan
    try {
        $configPath = Join-Path $installPath "config.json"
        $configContent = @{
            bot_token = $DiscordConfig.BotToken
            server_id = $DiscordConfig.ServerId
            channel_id = $DiscordConfig.ChannelId
            voicemeeter_path = $Prerequisites.VoiceMeeter.Path
            ffmpeg_path = $Prerequisites.FFmpeg.Path
            python_path = $Prerequisites.Python.Path
        }

        $configJson = $configContent | ConvertTo-Json
        $configJson | Set-Content -Path $configPath -Force -Encoding UTF8

        # Restrict config.json to current user only (CRITICAL: S2 fix)
        try {
            $acl = Get-Acl -Path $configPath
            $acl.SetAccessRuleProtection($true, $false)

            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            if ($currentUser) {
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $currentUser,
                    'FullControl',
                    'Allow'
                )
                $acl.SetAccessRule($rule)
                Set-Acl -Path $configPath -AclObject $acl -ErrorAction Stop
                Log-Message "Config file permissions restricted to current user" -LogPath $logPath
            }
        } catch {
            Log-Message "WARNING: Could not restrict config file permissions: $_" -LogPath $logPath
        }

        Log-Message "Configuration file created: $configPath" -LogPath $logPath
        Write-Host "      DONE" -ForegroundColor Green
    } catch {
        Log-Message "ERROR: Configuration file creation failed: $_" -LogPath $logPath
        Write-Host "      FAILED: $_" -ForegroundColor Red
        return @{ Success = $false; Error = "Config creation failed" }
    }

    # Copy bot files
    Write-Host "[5/6] Copying bot files..." -ForegroundColor Cyan
    try {
        $botSource = Get-BotFilesPath
        if ($botSource -and (Test-Path $botSource)) {
            Copy-Item -Path (Join-Path $botSource "bot.py") -Destination $installPath -Force -ErrorAction Stop
            Log-Message "Bot files copied to: $installPath" -LogPath $logPath
            Write-Host "      DONE" -ForegroundColor Green
        } else {
            Write-Host "      SKIPPED (bot.py not found)" -ForegroundColor Yellow
        }
    } catch {
        Log-Message "WARNING: Bot file copy failed (non-critical): $_" -LogPath $logPath
        Write-Host "      WARNING: $_" -ForegroundColor Yellow
    }

    # Final verification (R3: Prerequisites Verification)
    Write-Host "[6/6] Verifying installation..." -ForegroundColor Cyan
    try {
        $configExists = Test-Path $configPath
        $pythonOk = $Prerequisites.Python.Found
        $ffmpegOk = $Prerequisites.FFmpeg.Found
        $voicemeterOk = $Prerequisites.VoiceMeeter.Found

        if (-not $configExists) {
            throw "Config file not created"
        }

        if (-not $pythonOk) {
            throw "Python not detected after installation"
        }

        if (-not $ffmpegOk) {
            throw "FFmpeg not detected after installation"
        }

        if (-not $voicemeterOk) {
            throw "VoiceMeeter not detected - required for audio routing"
        }

        Log-Message "Installation verification: SUCCESS" -LogPath $logPath
        Write-Host "      DONE" -ForegroundColor Green
    } catch {
        Log-Message "ERROR: Installation verification failed: $_" -LogPath $logPath
        Write-Host "      FAILED: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "Missing prerequisites:" -ForegroundColor Red
        if (-not $configExists) { Write-Host "  - Configuration file" -ForegroundColor Red }
        if (-not $pythonOk) { Write-Host "  - Python 3.12 (get from https://www.python.org)" -ForegroundColor Red }
        if (-not $ffmpegOk) { Write-Host "  - FFmpeg (get from https://ffmpeg.org)" -ForegroundColor Red }
        if (-not $voicemeterOk) { Write-Host "  - VoiceMeeter (get from https://vb-audio.com/Voicemeeter/)" -ForegroundColor Red }
        return @{ Success = $false; Error = "Prerequisites verification failed" }
    }

    Write-Host ""
    Write-Host "Installation completed successfully!" -ForegroundColor Green -BackgroundColor DarkGreen
    Log-Message "Installation completed successfully" -LogPath $logPath
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Start the bot: python $installPath\bot.py" -ForegroundColor Gray
    Write-Host "2. Bot will connect to Discord channel: $($DiscordConfig.ChannelId)" -ForegroundColor Gray
    Write-Host "3. View logs: $logPath" -ForegroundColor Gray
    Write-Host ""

    return @{
        Success = $true
        InstallPath = $installPath
        ConfigPath = $configPath
        LogPath = $logPath
    }
}

function Log-Message {
    param(
        [string]$Message,
        [string]$LogPath
    )

    if (-not $LogPath) { return }

    $logDir = Split-Path -Parent $LogPath
    if (-not (Test-Path $logDir)) {
        try {
            New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null
        } catch {
            return
        }
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"

    try {
        Add-Content -Path $LogPath -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # Silently fail if log write fails
    }
}

function Get-RequirementsPath {
    # Multi-level resolution: module root → current → parent
    $path = "requirements.txt"

    # Level 1: Try module root (preferred)
    try {
        $moduleRoot = (Get-Module BATCRelayBot).ModuleBase
        if ($moduleRoot) {
            $modulePath = Join-Path $moduleRoot "requirements.txt"
            if (Test-Path $modulePath) { return $modulePath }
        }
    } catch {}

    # Level 2: Try current directory
    if (Test-Path $path) {
        return (Resolve-Path $path).Path
    }

    # Level 3: Try parent directory
    $parentPath = Join-Path ".." $path
    if (Test-Path $parentPath) {
        return (Resolve-Path $parentPath).Path
    }

    return $null
}

function Get-BotFilesPath {
    # Multi-level resolution: module root → current → parent
    # Level 1: Try module root (preferred)
    try {
        $moduleRoot = (Get-Module BATCRelayBot).ModuleBase
        if ($moduleRoot) {
            $botPath = Join-Path $moduleRoot "bot.py"
            if (Test-Path $botPath) { return $moduleRoot }
        }
    } catch {}

    # Level 2: Try current directory
    if (Test-Path "bot.py") {
        return (Resolve-Path ".").Path
    }

    # Level 3: Try parent directory
    if (Test-Path "..\bot.py") {
        return (Resolve-Path "..").Path
    }

    return $null
}

Export-ModuleMember -Function Start-Installation
