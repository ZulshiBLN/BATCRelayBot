#Requires -Version 5.1

<#
.SYNOPSIS
Asks which optional dependencies to remove (uninstaller phase 3).

.DESCRIPTION
Python and FFmpeg are asked about separately and removed only on explicit
confirmation. Neither is removed by default: you may well be using them for
something other than this bot, and the uninstaller cannot know.

Two things used to make this unusable. Detection ran `winget show`, which
queries the catalogue rather than the machine, so FFmpeg was offered even when
it was not installed. And only the literal string "yes" was accepted, so a "y"
fell through to the default and silently meant no.

VoiceMeeter is never offered: it ships audio drivers and must be removed with
VB-Audio's own uninstaller. It is named once, in the manual steps after the
removal, rather than here as well.

Neither is the PowerShell module. Uninstalling the module that is running the
uninstaller is a different decision from removing an installation, and the way
to do it - Uninstall-Module BATCRelayBot - is one line the summary can print.
#>

function Get-DependencyChoices {
    [OutputType([hashtable])]
    param(
        [hashtable]$Prerequisites = @{}
    )

    $choices = @{
        RemovePython          = $false
        RemoveFFmpeg          = $false
        PythonPackages        = @()
        FFmpegPackages        = @()
        SkipDependencyPrompts = $false
    }

    # The caller has already printed "[3/5] Optional components" above this.
    Write-Host "        Nothing here is removed unless you say so." -ForegroundColor Gray
    Write-Host ""

    if (-not (Test-WingetPresent)) {
        Write-Host "  winget is not available, so Python and FFmpeg cannot be removed" -ForegroundColor Yellow
        Write-Host "  automatically. Remove them via Settings > Apps if you want them gone." -ForegroundColor Gray
        Write-Host ""
        $choices.SkipDependencyPrompts = $true
        return $choices
    }

    # --- Python ---------------------------------------------------------
    Write-Host "1. Python" -ForegroundColor Cyan
    $pythonPackages = @(Get-InstalledWingetPackage -IdPrefix 'Python.Python' -IdPattern 'Python\.Python\.[\d.]+')

    if ($pythonPackages.Count -eq 0) {
        Write-Host "   Not installed via winget - nothing to remove here." -ForegroundColor Gray
    } else {
        foreach ($package in $pythonPackages) {
            Write-Host "   Found: $($package.Id)  ($($package.Version))" -ForegroundColor Gray
        }
        Write-Host "   WARNING: other software may depend on Python, and you may well be" -ForegroundColor Yellow
        Write-Host "   using it yourself. Removing it can break unrelated applications." -ForegroundColor Yellow
        Write-Host ""

        if (Read-YesNo -Question "   Remove Python?") {
            $choices.RemovePython = $true
            $choices.PythonPackages = $pythonPackages
        }
    }
    Write-Host ""

    # --- FFmpeg ---------------------------------------------------------
    Write-Host "2. FFmpeg" -ForegroundColor Cyan
    $ffmpegPackages = @(Get-InstalledWingetPackage -IdPrefix 'Gyan.FFmpeg' -IdPattern 'Gyan\.FFmpeg\S*')

    if ($ffmpegPackages.Count -eq 0) {
        Write-Host "   Not installed via winget - nothing to remove here." -ForegroundColor Gray
    } else {
        foreach ($package in $ffmpegPackages) {
            Write-Host "   Found: $($package.Id)  ($($package.Version))" -ForegroundColor Gray
        }
        Write-Host "   WARNING: FFmpeg is used by many media and streaming tools." -ForegroundColor Yellow
        Write-Host "   Removing it can break them." -ForegroundColor Yellow
        Write-Host ""

        if (Read-YesNo -Question "   Remove FFmpeg?") {
            $choices.RemoveFFmpeg = $true
            $choices.FFmpegPackages = $ffmpegPackages
        }
    }
    Write-Host ""

    return $choices
}

function Read-YesNo {
    <#
    .SYNOPSIS
    Asks a yes/no question that defaults to no.

    .DESCRIPTION
    Accepts the short and long forms in English and German, because the
    previous version only recognised the exact word "yes" and treated
    everything else - "y" included - as a silent no.

    Defaults to no on empty input and on a non-interactive host, so an
    automated run never removes anything by accident.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$Question
    )

    try {
        $answer = Read-Host "$Question [y/N]"
    } catch {
        Write-Host "   (no input available - keeping it)" -ForegroundColor Gray
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($answer)) { return $false }

    return ($answer.Trim() -match '^(y|yes|j|ja)$')
}

Export-ModuleMember -Function @('Get-DependencyChoices', 'Read-YesNo')
