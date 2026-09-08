function Confirm-ConfigEditorPrerequisites {
    <#
    .SYNOPSIS
    Validates prerequisites for config editor before allowing changes.

    .DESCRIPTION
    Checks installation directory, config.json access, file permissions, and bot status.
    Returns validation result with details for decision-making.

    .PARAMETER InstallPath
    Path to BATCRelayBot installation (default: $env:LOCALAPPDATA\BATCRelayBot)

    .OUTPUTS
    Hashtable with properties:
    - Valid (bool): Overall validation result
    - InstallPath (string): Validated installation path
    - ConfigPath (string): Full path to config.json (if found)
    - BotRunning (bool): Whether bot process is currently running
    - Errors (array): List of validation errors (if any)

    .EXAMPLE
    $result = Confirm-ConfigEditorPrerequisites
    if ($result.Valid) {
        Write-Host "Ready to edit config"
    } else {
        $result.Errors | ForEach-Object { Write-Warning $_ }
    }
    #>

    param(
        [string]$InstallPath = (Join-Path $env:LOCALAPPDATA "BATCRelayBot")
    )

    $errors = [System.Collections.ArrayList]@()

    # Step 1: Check installation directory exists
    if (-not (Test-Path $InstallPath -PathType Container)) {
        $errors.Add("Installation directory not found: $InstallPath") | Out-Null
    }

    # Step 2: Locate and validate config.json
    $configPath = Join-Path $InstallPath "config.json"
    if (-not (Test-Path $configPath -PathType Leaf)) {
        $errors.Add("config.json not found at $configPath") | Out-Null
    }

    # Step 3: Verify read/write permissions
    if ($errors.Count -eq 0) {
        $probeFile = "$configPath.probe"
        try {
            Get-Content $configPath -Raw -ErrorAction Stop | Out-Null
            [System.IO.File]::WriteAllText($probeFile, "probe")
        }
        catch {
            $errors.Add("No read/write access to config.json: $($_.Exception.Message)") | Out-Null
        }
        finally {
            # Always clean up, including when the write itself failed part way.
            Remove-Item $probeFile -Force -ErrorAction SilentlyContinue
        }
    }

    # Step 4: Detect running bot.
    # Not Get-Process: a Process object has no CommandLine property on
    # Windows PowerShell 5.1, so the old check matched nothing and the
    # "changes need a restart" warning never appeared. Find-BotProcess reads
    # Win32_Process and also covers pythonw.exe, which is what
    # Start-BATCRelayBot launches.
    $botRunning = @(Find-BotProcess -BotPath $InstallPath).Count -gt 0

    # Step 5: Return validation result
    $valid = $errors.Count -eq 0

    return @{
        Valid       = $valid
        InstallPath = $InstallPath
        ConfigPath  = if ($valid) { $configPath } else { $null }
        BotRunning  = $botRunning
        Errors      = $errors
    }
}
