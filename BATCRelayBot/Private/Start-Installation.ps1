#Requires -Version 5.1

<#
.SYNOPSIS
Performs the installation itself, once everything has been resolved.

.DESCRIPTION
By the time this runs, prerequisites are present and the configuration has
been collected and confirmed. It only writes files.

The winget auto-install that used to live here has moved to phase 3 of
Install-BATCRelayBot. Keeping it here duplicated the copy in the public
function and ran after the readiness check that it was supposed to satisfy.
#>

function Start-Installation {
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Prerequisites,

        [Parameter(Mandatory = $true)]
        [hashtable]$DiscordConfig,

        [string]$InstallPath = (Join-Path $env:LOCALAPPDATA "BATCRelayBot"),

        [string]$LogPath
    )

    if (-not $LogPath) { $LogPath = Join-Path $InstallPath "install.log" }
    $configPath = Join-Path $InstallPath "config.json"

    Write-Host ""

    # ---- 1: directory ---------------------------------------------------
    Write-Host "  [1/4] Installation directory" -ForegroundColor Gray
    try {
        if (-not (Test-Path $InstallPath)) {
            New-Item -ItemType Directory -Path $InstallPath -Force -ErrorAction Stop | Out-Null
        }
        Write-InstallLog "Installation directory ready: $InstallPath" -LogPath $LogPath
        Write-Host "        OK  $InstallPath" -ForegroundColor Green
    } catch {
        $message = Remove-SensitiveData -Text $_.Exception.Message
        Write-InstallLog "Could not create $($InstallPath): $message" -LogPath $LogPath -Level ERROR
        Write-Host "        FAILED: $message" -ForegroundColor Red
        return @{ Success = $false; Error = "Could not create the installation directory" }
    }

    # ---- 2: python dependencies -----------------------------------------
    Write-Host "  [2/4] Python dependencies" -ForegroundColor Gray
    $requirementsPath = Get-RequirementsPath
    if (-not $requirementsPath) {
        Write-InstallLog "requirements.txt not found in any known location" -LogPath $LogPath -Level ERROR
        Write-Host "        FAILED: requirements.txt not found" -ForegroundColor Red
        return @{ Success = $false; Error = "requirements.txt not found" }
    }

    try {
        Write-InstallLog "pip install -r $requirementsPath" -LogPath $LogPath
        $pipOutput = & $Prerequisites.Python.Path -m pip install -r $requirementsPath --disable-pip-version-check 2>&1 |
            ForEach-Object { "$_" }

        if ($LASTEXITCODE -ne 0) {
            foreach ($line in ($pipOutput | Select-Object -Last 10)) {
                Write-InstallLog "pip: $line" -LogPath $LogPath -Level ERROR
            }
            Write-Host "        FAILED: pip exited with code $LASTEXITCODE" -ForegroundColor Red
            Write-Host "        See the log for pip's output: $LogPath" -ForegroundColor Yellow
            return @{ Success = $false; Error = "Installing Python dependencies failed" }
        }

        Write-InstallLog "Python dependencies installed" -LogPath $LogPath
        Write-Host "        OK  discord.py and dependencies installed" -ForegroundColor Green
    } catch {
        $message = Remove-SensitiveData -Text $_.Exception.Message
        Write-InstallLog "pip failed: $message" -LogPath $LogPath -Level ERROR
        Write-Host "        FAILED: $message" -ForegroundColor Red
        return @{ Success = $false; Error = "Installing Python dependencies failed" }
    }

    # ---- 3: bot files ---------------------------------------------------
    Write-Host "  [3/4] Bot files" -ForegroundColor Gray
    $botSource = Get-BotFilesPath
    if (-not $botSource) {
        Write-InstallLog "bot.py not found in any known location" -LogPath $LogPath -Level ERROR
        Write-Host "        FAILED: bot.py not found" -ForegroundColor Red
        return @{ Success = $false; Error = "bot.py not found" }
    }

    try {
        Copy-Item -Path (Join-Path $botSource "bot.py") -Destination $InstallPath -Force -ErrorAction Stop
        Write-InstallLog "bot.py copied from $botSource" -LogPath $LogPath
        Write-Host "        OK  bot.py" -ForegroundColor Green
    } catch {
        $message = Remove-SensitiveData -Text $_.Exception.Message
        Write-InstallLog "Copying bot.py failed: $message" -LogPath $LogPath -Level ERROR
        Write-Host "        FAILED: $message" -ForegroundColor Red
        return @{ Success = $false; Error = "Could not copy bot.py" }
    }

    # ---- 4: configuration -----------------------------------------------
    Write-Host "  [4/4] Configuration" -ForegroundColor Gray
    try {
        New-BotConfigFile -ConfigPath $configPath `
            -Prerequisites $Prerequisites -DiscordConfig $DiscordConfig | Out-Null

        Write-InstallLog "config.json written to $configPath" -LogPath $LogPath
        Write-Host "        OK  config.json (readable only by you)" -ForegroundColor Green
    } catch {
        $message = Remove-SensitiveData -Text $_.Exception.Message
        Write-InstallLog "Writing config.json failed: $message" -LogPath $LogPath -Level ERROR
        Write-Host "        FAILED: $message" -ForegroundColor Red
        return @{ Success = $false; Error = "Could not write config.json" }
    }

    # ---- verification ---------------------------------------------------
    # Verify what was produced, not what was intended: this is the check that
    # would have caught the config schema mismatch years ago.
    $verification = Test-InstallationResult -InstallPath $InstallPath -ConfigPath $configPath
    if (-not $verification.Valid) {
        foreach ($problem in $verification.Problems) {
            Write-InstallLog "Verification failed: $problem" -LogPath $LogPath -Level ERROR
            Write-Host "        $problem" -ForegroundColor Red
        }
        return @{ Success = $false; Error = "Verification of the installed files failed" }
    }

    Write-InstallLog "Verification passed" -LogPath $LogPath

    return @{
        Success     = $true
        InstallPath = $InstallPath
        ConfigPath  = $configPath
        LogPath     = $LogPath
    }
}

function Test-InstallationResult {
    <#
    .SYNOPSIS
    Checks that the files on disk are actually usable by the bot.

    .DESCRIPTION
    Re-reads config.json and confirms every key bot.py declares in
    REQUIRED_KEYS is present and non-empty, reading the list from the
    installed bot.py so the two cannot drift apart.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][string]$InstallPath,
        [Parameter(Mandatory = $true)][string]$ConfigPath
    )

    $problems = @()

    $botPath = Join-Path $InstallPath "bot.py"
    if (-not (Test-Path $botPath)) { $problems += "bot.py is missing from $InstallPath" }
    if (-not (Test-Path $ConfigPath)) { $problems += "config.json is missing from $InstallPath" }

    if ($problems.Count -gt 0) {
        return @{ Valid = $false; Problems = $problems }
    }

    $config = $null
    try {
        $config = Get-Content $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return @{ Valid = $false; Problems = @("config.json is not valid JSON: $($_.Exception.Message)") }
    }

    $requiredKeys = @('bot_token', 'guild_id', 'voice_channel_id', 'audio_device_name')
    try {
        $botSource = Get-Content $botPath -Raw -ErrorAction Stop
        if ($botSource -match 'REQUIRED_KEYS\s*=\s*\[(.*?)\]') {
            $parsed = [regex]::Matches($Matches[1], '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
            if ($parsed) { $requiredKeys = $parsed }
        }
    } catch {
        # Fall back to the hardcoded list above.
    }

    foreach ($key in $requiredKeys) {
        if (-not ($config.PSObject.Properties.Name -contains $key)) {
            $problems += "config.json is missing the key '$key' that bot.py requires"
        } elseif ([string]::IsNullOrWhiteSpace([string]$config.$key)) {
            $problems += "config.json has an empty value for '$key', which bot.py rejects"
        }
    }

    return @{ Valid = ($problems.Count -eq 0); Problems = $problems }
}

function Get-RequirementsPath {
    <#
    .SYNOPSIS
    Locates requirements.txt for both PSGallery and repository layouts.
    #>
    [OutputType([string])]
    param()

    $candidates = @()

    try {
        $moduleBase = (Get-Module BATCRelayBot).ModuleBase
        if ($moduleBase) {
            $candidates += Join-Path $moduleBase "requirements.txt"
            $candidates += Join-Path (Split-Path -Parent $moduleBase) "requirements.txt"
        }
    } catch {}

    $candidates += "requirements.txt"
    $candidates += (Join-Path ".." "requirements.txt")

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }
    return $null
}

function Get-BotFilesPath {
    <#
    .SYNOPSIS
    Locates the directory containing bot.py.
    #>
    [OutputType([string])]
    param()

    $candidates = @()

    try {
        $moduleBase = (Get-Module BATCRelayBot).ModuleBase
        if ($moduleBase) {
            $candidates += $moduleBase
            $candidates += (Split-Path -Parent $moduleBase)
        }
    } catch {}

    $candidates += "."
    $candidates += ".."

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path (Join-Path $candidate "bot.py"))) {
            return (Resolve-Path $candidate).Path
        }
    }
    return $null
}

Export-ModuleMember -Function @(
    'Start-Installation',
    'Test-InstallationResult',
    'Get-RequirementsPath',
    'Get-BotFilesPath'
)
