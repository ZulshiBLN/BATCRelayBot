#Requires -Version 5.1

function Format-Snowflake {
    <#
    .SYNOPSIS
    Renders a Discord ID as "..." and its last four digits - enough to
    recognise the server, nothing to copy.

    .DESCRIPTION
    Setup output and the editor's menu travel into screenshots and bug
    reports, which is what the secrets rule is about. Whoever needs the full
    ID copies it from Discord, where it came from. Used by the installation
    summary, the keep question and the editor - one helper, so the three
    screens cannot drift.
    #>
    [OutputType([string])]
    param($Value)

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return "(not set)" }
    $text = $text.Trim()
    if ($text.Length -le 4) { return "..." + $text }
    return "..." + $text.Substring($text.Length - 4)
}

Export-ModuleMember -Function @('Format-Snowflake')
