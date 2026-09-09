function Out-CommandResult {
    <#
    .SYNOPSIS
    Emits a command's result object only when the caller asked for it.

    .DESCRIPTION
    A public command returns a result object so it can be scripted against.
    PowerShell writes any return value nothing consumes to the screen, which is
    where the "Name / Value" block after every install, uninstall and edit came
    from - install paths listed twice, "Success" in the middle of the output,
    and a cancelled run reported as a table.

    Every public command routes its return through here, so the rule lives in
    one place instead of at fourteen return statements.

    Returning nothing from here is genuinely nothing: "return (Out-CommandResult
    ...)" in the caller adds no $null to the pipeline when the switch is off.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Result,

        [switch]$PassThru
    )

    if ($PassThru) { $Result }
}
