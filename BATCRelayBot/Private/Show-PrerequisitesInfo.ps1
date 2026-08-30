#Requires -Version 5.1

<#
.SYNOPSIS
Display prerequisites status information (read-only info screen)

.DESCRIPTION
Shows what's installed, what's missing, what's optional in a user-friendly format.
No prompts, just information display.

Phase 2 of installer refactoring: Information Display
#>

function Show-PrerequisitesInfo {
    [OutputType([void])]
    param()

    Write-Host ""
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host "       BATCRelayBot Installation - Prerequisites Check" -ForegroundColor Cyan
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host ""

    # Detect prerequisites
    $python = Find-Python
    $ffmpeg = Find-FFmpeg
    $voicemeeter = Find-VoiceMeeter
    $beyondatc = Find-BeyondATC

    # Display results
    Write-Host "Prerequisites Status:" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ""

    # Python (REQUIRED)
    Write-Host "  [*] Python 3.10+ (REQUIRED)" -ForegroundColor White
    if ($python.Found) {
        Write-Host "      FOUND: $($python.Path)" -ForegroundColor Green
        Write-Host "      Version: $($python.Version)" -ForegroundColor Green
        Write-Host "      Source: $($python.Method)" -ForegroundColor DarkGreen
    } else {
        Write-Host "      NOT FOUND - Installation will fail" -ForegroundColor Red
        Write-Host "      Download: https://www.python.org/downloads/" -ForegroundColor Yellow
    }
    Write-Host ""

    # FFmpeg (REQUIRED)
    Write-Host "  [*] FFmpeg (REQUIRED)" -ForegroundColor White
    if ($ffmpeg.Found) {
        Write-Host "      FOUND: $($ffmpeg.Path)" -ForegroundColor Green
        Write-Host "      Version: $($ffmpeg.Version)" -ForegroundColor Green
        Write-Host "      Source: $($ffmpeg.Method)" -ForegroundColor DarkGreen
    } else {
        Write-Host "      NOT FOUND - Installation will fail" -ForegroundColor Red
        Write-Host "      Install: winget install Gyan.FFmpeg" -ForegroundColor Yellow
    }
    Write-Host ""

    # VoiceMeeter (REQUIRED)
    Write-Host "  [*] VoiceMeeter (REQUIRED for audio routing)" -ForegroundColor White
    if ($voicemeeter.Found) {
        Write-Host "      FOUND: $($voicemeeter.Path)" -ForegroundColor Green
        Write-Host "      Version: $($voicemeeter.Version)" -ForegroundColor Green
        Write-Host "      Source: $($voicemeeter.Method)" -ForegroundColor DarkGreen
    } else {
        Write-Host "      NOT FOUND - Audio streaming won't work" -ForegroundColor Red
        Write-Host "      Download: https://vb-audio.com/Voicemeeter/" -ForegroundColor Yellow
        Write-Host "      Note: Manual installation required" -ForegroundColor Yellow
    }
    Write-Host ""

    # BeyondATC (OPTIONAL)
    Write-Host "  [o] BeyondATC (OPTIONAL - only for ATC relay)" -ForegroundColor White
    if ($beyondatc.Found) {
        Write-Host "      FOUND: $($beyondatc.Path)" -ForegroundColor Green
        Write-Host "      Version: $($beyondatc.Version)" -ForegroundColor Green
        Write-Host "      Source: $($beyondatc.Method)" -ForegroundColor DarkGreen
    } else {
        Write-Host "      Not installed (optional)" -ForegroundColor Gray
        Write-Host "      Info: Needed only for ATC relay feature" -ForegroundColor DarkGray
    }
    Write-Host ""

    # Summary
    $requiredFound = @($python.Found, $ffmpeg.Found, $voicemeeter.Found) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
    $requiredTotal = 3

    Write-Host "Summary:" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ""

    $requiredColor = if ($requiredFound -eq $requiredTotal) { 'Green' } else { 'Red' }
    Write-Host "  Required: $requiredFound/$requiredTotal installed" -ForegroundColor $requiredColor

    if ($beyondatc.Found) {
        Write-Host "  Optional: BeyondATC installed" -ForegroundColor Green
    } else {
        Write-Host "  Optional: BeyondATC not installed (optional)" -ForegroundColor Gray
    }
    Write-Host ""

    # Readiness
    if ($requiredFound -eq $requiredTotal) {
        Write-Host "  >>> Installation can proceed! <<<" -ForegroundColor Green -BackgroundColor DarkGreen
    } else {
        Write-Host "  >>> Missing required prerequisites. Installation will fail. <<<" -ForegroundColor Red -BackgroundColor DarkRed
    }
    Write-Host ""
}

Export-ModuleMember -Function 'Show-PrerequisitesInfo'
