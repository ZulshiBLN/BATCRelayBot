#Requires -Version 5.1

<#
.SYNOPSIS
Installation logging that exists from the first line of the installer.

.DESCRIPTION
Until 1.4.0 the log directory was created in installation step 1, and the
first log call happened after that - so every failure during detection,
Discord entry or the readiness check produced no log at all. Combined with
the window closing on exit, that made the most common failures completely
undiagnosable.

Initialize-InstallLog is therefore called before anything else can fail, and
logging never throws: a broken log must not abort an install.
#>

function Initialize-InstallLog {
    <#
    .SYNOPSIS
    Creates the install directory and starts a fresh log session.

    .OUTPUTS
    Path to the log file, or $null if it could not be created.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,

        [string]$Version = "unknown"
    )

    try {
        if (-not (Test-Path $InstallPath)) {
            New-Item -ItemType Directory -Path $InstallPath -Force -ErrorAction Stop | Out-Null
        }
        $logPath = Join-Path $InstallPath "install.log"

        # UTF8 (not UTF8NoBOM): the NoBOM variant only exists in PowerShell 6+
        # and silently failed every log write on Windows PowerShell 5.1.
        Add-Content -Path $logPath -Encoding UTF8 -ErrorAction Stop -Value @(
            "",
            "==================================================",
            "Installation session started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "BATCRelayBot $Version on PowerShell $($PSVersionTable.PSVersion) / $([System.Environment]::OSVersion.VersionString)",
            "=================================================="
        )
        return $logPath
    } catch {
        Write-Host "WARNING: Could not create the log file under $InstallPath" -ForegroundColor Yellow
        Write-Host "         $($_.Exception.Message)" -ForegroundColor Yellow
        return $null
    }
}

function Write-InstallLog {
    <#
    .SYNOPSIS
    Appends one line to the installation log. Never throws.
    #>
    param(
        [string]$Message,
        [string]$LogPath,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    if ([string]::IsNullOrWhiteSpace($LogPath)) { return }

    try {
        $logDir = Split-Path -Parent $LogPath
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null
        }

        $safe = Remove-SensitiveData -Text $Message
        $entry = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $safe
        Add-Content -Path $LogPath -Value $entry -Encoding UTF8 -ErrorAction Stop
    } catch {
        # A log that cannot be written must not take the installation down.
    }
}

function Remove-SensitiveData {
    <#
    .SYNOPSIS
    Redacts bot tokens before anything reaches the log or the console.

    .DESCRIPTION
    Discord bot tokens are three base64url segments separated by dots. The
    first segment is the bot's user ID and is not secret, but the remainder
    is, so the whole value is replaced rather than partially shown.
    #>
    [OutputType([string])]
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $redacted = [regex]::Replace(
        $Text,
        '[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]{20,}',
        '[REDACTED-TOKEN]')

    # Also catch a token that appears behind an Authorization header.
    $redacted = [regex]::Replace($redacted, '(?i)(Bot\s+)[A-Za-z0-9_\-\.]{30,}', '$1[REDACTED-TOKEN]')

    return $redacted
}

Export-ModuleMember -Function @('Initialize-InstallLog', 'Write-InstallLog', 'Remove-SensitiveData')
