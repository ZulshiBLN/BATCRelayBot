function Confirm-ConfigEditorPrerequisites {
    <#
    .SYNOPSIS
    Validates prerequisites for config editor before allowing changes.

    .DESCRIPTION
    Checks installation directory, config.json access, file permissions, and bot status.
    Returns validation result with details for decision-making.

    .PARAMETER InstallPath
    Path to BATCRelayBot installation (default: $env:USERPROFILE\AppData\Local\BATCRelayBot)

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
        [string]$InstallPath = "$env:USERPROFILE\AppData\Local\BATCRelayBot"
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
        try {
            $testRead = Get-Content $configPath -Raw -ErrorAction Stop
            $tempFile = "$configPath.test"
            [System.IO.File]::WriteAllText($tempFile, "test")
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
        catch {
            $errors.Add("No read/write permissions: $_") | Out-Null
        }
    }

    # Step 4: Detect running bot (python process with bot.py)
    $botRunning = $null -ne (Get-Process python -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "bot\.py" })

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
