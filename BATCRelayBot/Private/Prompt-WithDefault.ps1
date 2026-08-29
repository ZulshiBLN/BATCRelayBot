function Prompt-WithDefault {
    param(
        [string]$Message,
        [string]$Default
    )

    if ($Default) {
        $input = Read-Host "$Message [$Default]"
        if ([string]::IsNullOrWhiteSpace($input)) { return $Default }
        return $input
    } else {
        $input = ""
        while ([string]::IsNullOrWhiteSpace($input)) {
            $input = Read-Host $Message
            if ([string]::IsNullOrWhiteSpace($input)) {
                Write-Host "This field cannot be empty." -ForegroundColor Yellow
            }
        }
        return $input
    }
}
