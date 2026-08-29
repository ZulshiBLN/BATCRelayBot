# Dot-source all private functions
$privateFunctions = @(Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue)
foreach ($function in $privateFunctions) {
    . $function.FullName
}

# Dot-source all public functions
$publicFunctions = @(Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue)
foreach ($function in $publicFunctions) {
    . $function.FullName
}

Export-ModuleMember -Function @(
    'Install-BATCRelayBot',
    'Start-BATCRelayBot',
    'Stop-BATCRelayBot',
    'Uninstall-BATCRelayBot',
    'Get-BATCRelayBotStatus'
)
