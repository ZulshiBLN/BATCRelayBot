function Find-PerUserPython {
    $base = Join-Path $env:LOCALAPPDATA "Programs\Python"
    if (-not (Test-Path $base)) { return $null }

    $candidates = Get-ChildItem $base -Directory -Filter "Python3*" -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "python.exe") } |
        Sort-Object Name -Descending

    if ($candidates) {
        return Join-Path $candidates[0].FullName "python.exe"
    }
    return $null
}
