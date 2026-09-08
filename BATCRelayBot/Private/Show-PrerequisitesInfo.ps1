#Requires -Version 5.1

<#
.SYNOPSIS
Displays prerequisite status. Read-only, no prompts.

.DESCRIPTION
Takes the detection results as a parameter instead of detecting again.
Running detection a second time cost several seconds and could disagree with
the results the rest of the installer was working from.
#>

function Show-PrerequisitesInfo {
    [OutputType([void])]
    param(
        [hashtable]$Prerequisites
    )

    # Detect only when called without results, so the function stays usable
    # on its own for troubleshooting.
    if (-not $Prerequisites) {
        $Prerequisites = @{
            Python      = Find-Python
            FFmpeg      = Find-FFmpeg
            VoiceMeeter = Find-VoiceMeeter
            BeyondATC   = Find-BeyondATC
        }
    }

    Write-Host ""
    Write-Host "  Component      Status" -ForegroundColor DarkGray
    Write-Host "  ---------------------------------------------------------------" -ForegroundColor DarkGray

    # No download links here. This phase reports state; whatever is missing is
    # named again in phase 3 with the link beside it, and printing them twice
    # is most of what made the installer feel cluttered.
    Write-PrerequisiteLine -Name "Python"      -Item $Prerequisites.Python      -Requirement "required"
    Write-PrerequisiteLine -Name "FFmpeg"      -Item $Prerequisites.FFmpeg      -Requirement "required"
    Write-PrerequisiteLine -Name "VoiceMeeter" -Item $Prerequisites.VoiceMeeter -Requirement "required"
    Write-PrerequisiteLine -Name "BeyondATC"   -Item $Prerequisites.BeyondATC   -Requirement "optional"

    Write-Host ""
}

function Write-PrerequisiteLine {
    <#
    .SYNOPSIS
    Renders one status row, with the reason when something is missing.
    #>
    param(
        [string]$Name,
        [hashtable]$Item,
        [string]$Requirement
    )

    $label = "  {0,-14}" -f $Name

    if ($Item.Found) {
        $detail = if ($Item.Version -and $Item.Version -ne "Unknown") { " ($($Item.Version))" } else { "" }
        Write-Host "$label FOUND$detail" -ForegroundColor Green
        if ($Item.Path) {
            Write-Host ("{0} {1}" -f (" " * 16), $Item.Path) -ForegroundColor DarkGray
        }
    } else {
        $color = if ($Requirement -eq 'optional') { 'Gray' } else { 'Red' }
        $word = if ($Requirement -eq 'optional') { "not installed (optional)" } else { "MISSING" }
        Write-Host "$label $word" -ForegroundColor $color

        # An optional component's reason restates its status word for word -
        # "not installed (optional)" under "not installed (optional)". The
        # reason earns its line only where it says something new, which is when
        # something required is missing and the user needs to know why.
        if ($Item.Reason -and $Requirement -ne 'optional') {
            Write-Host ("{0} {1}" -f (" " * 16), $Item.Reason) -ForegroundColor DarkGray
        }
    }
}

Export-ModuleMember -Function @('Show-PrerequisitesInfo', 'Write-PrerequisiteLine')
