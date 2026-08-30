function Get-OutputFormat {
    <#
    .SYNOPSIS
    Displays menu for output format selection.

    .PARAMETER CurrentFormat
    Current output format (standard, compact, verbose)

    .OUTPUTS
    Hashtable with properties: Value, Valid, Message, Field
    #>

    param(
        [string]$CurrentFormat
    )

    $formats = @("standard", "compact", "verbose")

    Write-Host ""
    Write-Host "Output Format"
    Write-Host "Current: $CurrentFormat"
    Write-Host ""
    Write-Host "1. standard  - Full output with timestamps"
    Write-Host "2. compact   - Minimal output"
    Write-Host "3. verbose   - Detailed output with debug info"
    Write-Host ""

    $selection = Read-Host "Select format (1-3, or press Enter to skip)"

    if ($selection -eq "") {
        return @{
            Value   = $null
            Valid   = $false
            Message = "Selection cancelled"
        }
    }

    $selectionMap = @{
        "1" = "standard"
        "2" = "compact"
        "3" = "verbose"
    }

    if ($selectionMap.ContainsKey($selection)) {
        $format = $selectionMap[$selection]
        return @{
            Value   = $format
            Valid   = $true
            Message = "Format selected: $format"
            Field   = "Format"
        }
    }

    return @{
        Value   = $null
        Valid   = $false
        Message = "Invalid selection (must be 1, 2, or 3)"
    }
}
