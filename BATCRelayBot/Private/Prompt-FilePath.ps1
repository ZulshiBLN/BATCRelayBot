function Prompt-FilePath {
    param(
        [string]$Message,
        [string]$Filter
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms | Out-Null
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = $Message
        $dialog.Filter = $Filter
        Write-Host "$Message (opening file picker...)" -ForegroundColor Cyan
        $result = $dialog.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.FileName
        }
    } catch {
        Write-Host "Graphical file picker not available, please enter the path manually." -ForegroundColor Yellow
    }
    return Prompt-WithDefault -Message $Message -Default $null
}
