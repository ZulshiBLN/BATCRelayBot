function Find-FfmpegExe {
    $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $wingetPkgDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $wingetPkgDir) {
        $found = Get-ChildItem $wingetPkgDir -Filter "ffmpeg.exe" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "Gyan\.FFmpeg" } |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    return $null
}
