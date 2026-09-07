#Requires -Version 5.1

function Verify-ConfigChange {
    <#
    .SYNOPSIS
    Re-reads config.json and confirms the field really holds the new value.

    .DESCRIPTION
    The point of this check is that it reads from disk rather than trusting
    the write. A mismatch triggers a rollback in Edit-BATCRelayBotConfig.

    Comparison is type-aware: the ID fields are stored as JSON numbers, so a
    string comparison against what the user typed would fail even on a
    correct write.

    .PARAMETER ConfigPath
    Path to config.json.

    .PARAMETER Field
    Editor field name (Token, Guild, Channel, AudioDevice).

    .PARAMETER ExpectedValue
    The value that should now be stored.

    .OUTPUTS
    Hashtable with Verified, WrittenValue, Message.
    #>
    param(
        [string]$ConfigPath,
        [string]$Field,
        $ExpectedValue
    )

    try {
        $definition = Get-ConfigFieldDefinition -Field $Field
        $expected = ConvertTo-ConfigFieldValue -Field $Field -Value $ExpectedValue
    } catch {
        return @{
            Verified     = $false
            WrittenValue = $null
            Message      = $_.Exception.Message
        }
    }

    try {
        $written = Get-Content $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return @{
            Verified     = $false
            WrittenValue = $null
            Message      = "config.json could not be read back: $($_.Exception.Message)"
        }
    }

    $actual = $written.($definition.Json)

    # Not $matches: that is PowerShell's automatic regex-capture variable.
    $isMatch = if ($definition.Type -eq 'long') {
        # Compare as numbers so 123 and "123" are not reported as different.
        ($null -ne $actual) -and ([string]$actual -eq [string]$expected)
    } else {
        $actual -ceq $expected
    }

    if ($isMatch) {
        return @{
            Verified     = $true
            WrittenValue = $actual
            Message      = "$($definition.Label) verified"
        }
    }

    # Never echo the token itself into a message that may be logged or pasted
    # into a bug report.
    $detail = if ($Field -eq 'Token') {
        "Token verification failed - the saved value does not match what was entered"
    } else {
        "$($definition.Label) verification failed - config.json holds '$actual'"
    }

    return @{
        Verified     = $false
        WrittenValue = $actual
        Message      = $detail
    }
}

Export-ModuleMember -Function Verify-ConfigChange
