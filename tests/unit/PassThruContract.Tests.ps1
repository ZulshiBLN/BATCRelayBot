# Public commands return a result object so they can be scripted against.
# PowerShell writes any return value nothing consumes straight to the screen,
# which is where the "Name / Value" block after every install, uninstall and
# edit came from: install paths listed a second time, "Success" in the middle
# of the report, and a deliberate quit shown as a table.
#
# The contract is now: nothing reaches the success stream unless the caller
# asked with -PassThru.
#
# Both halves are tested. A behavioural test alone passes while a single
# forgotten return path still dumps; a structural test alone passes while the
# switch is wired up and does nothing.

BeforeAll {
    $ModuleRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'BATCRelayBot'
    Import-Module (Join-Path $ModuleRoot 'BATCRelayBot.psd1') -Force

    # Never a real installation. The commands below are genuinely invoked, and
    # a path that exists would take a different branch entirely.
    $Sandbox = Join-Path $env:TEMP ("passthru-" + [guid]::NewGuid().ToString('N'))

    # The commands are not listed here by hand: a fifth one added later has to
    # be covered without anyone remembering to extend this file.
    $Exported = (Import-PowerShellDataFile (Join-Path $ModuleRoot 'BATCRelayBot.psd1')).FunctionsToExport

    # An exported command "emits" when it has a return statement carrying a
    # value. Those are the ones that can dump, and the only ones that need the
    # switch - Start- and Stop-BATCRelayBot use bare returns and need nothing.
    function Get-ValueReturn {
        param([string]$Command)

        $file = Join-Path $ModuleRoot "Public\$Command.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)

        $function = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $Command
        }, $true)

        # Searching from the function node keeps private helpers defined beside
        # it in the same file out of the result - they are siblings, not nested.
        @($function.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.ReturnStatementAst] -and
            $null -ne $node.Pipeline
        }, $true))
    }
}

AfterAll {
    Remove-Item $Sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "-PassThru contract" {

    Context "a plain call writes nothing to the success stream" {

        It "Get-BATCRelayBotStatus" {
            @(Get-BATCRelayBotStatus -BotPath $Sandbox).Count | Should -Be 0
        }

        # Mocked rather than pointed at a missing directory: this must reach the
        # early return deterministically, and a wrong turn here would otherwise
        # end at a Read-Host that never returns on a build agent.
        It "Uninstall-BATCRelayBot, when there is nothing to remove" {
            InModuleScope BATCRelayBot {
                Mock Confirm-UninstallPrerequisites {
                    @{ Valid = $false; Errors = @("No installation found"); Warnings = @() }
                }
                @(Uninstall-BATCRelayBot -InstallPath 'C:\does-not-exist').Count | Should -Be 0
            }
        }

        It "Uninstall-BATCRelayBot, after it actually removed something" {
            InModuleScope BATCRelayBot {
                Mock Confirm-UninstallPrerequisites {
                    @{ Valid = $true; InstallPath = 'C:\does-not-exist'; Errors = @(); Warnings = @() }
                }
                Mock Show-RemovalSummary { @{} }
                Mock Get-DependencyChoices { @{} }
                Mock Invoke-SecureUninstall { @{ Success = $true; DeletedFiles = @(); Errors = @() } }
                Mock Show-PostRemovalSummary { }

                @(Uninstall-BATCRelayBot -InstallPath 'C:\does-not-exist' -Force).Count | Should -Be 0
            }
        }

        It "Edit-BATCRelayBotConfig, with no installation to edit" {
            InModuleScope BATCRelayBot {
                Mock Confirm-ConfigEditorPrerequisites {
                    @{ Valid = $false; Errors = @("No config.json"); BotRunning = $false }
                }
                @(Edit-BATCRelayBotConfig -InstallPath 'C:\does-not-exist').Count | Should -Be 0
            }
        }

        # Every failing exit of Install-BATCRelayBot goes through here, so this
        # one function stands for all seven of them. Read-Host is mocked because
        # Stop-Installation pauses whenever the session is interactive.
        It "Install-BATCRelayBot, on the path every failure takes" {
            InModuleScope BATCRelayBot {
                Mock Read-Host { '' }
                @(Stop-Installation -Reason 'test' -LogPath $null).Count | Should -Be 0
            }
        }
    }

    Context "-PassThru returns the object" {

        It "Get-BATCRelayBotStatus returns its status" {
            $status = Get-BATCRelayBotStatus -BotPath $Sandbox -PassThru
            $status | Should -Not -BeNullOrEmpty
            $status.IsRunning | Should -Be $false
        }

        It "Uninstall-BATCRelayBot returns the failure it reported" {
            InModuleScope BATCRelayBot {
                Mock Confirm-UninstallPrerequisites {
                    @{ Valid = $false; Errors = @("No installation found"); Warnings = @() }
                }
                $result = Uninstall-BATCRelayBot -InstallPath 'C:\does-not-exist' -PassThru
                $result.Success | Should -Be $false
                $result.Errors | Should -Contain "No installation found"
            }
        }

        It "Edit-BATCRelayBotConfig returns the failure it reported" {
            InModuleScope BATCRelayBot {
                Mock Confirm-ConfigEditorPrerequisites {
                    @{ Valid = $false; Errors = @("No config.json"); BotRunning = $false }
                }
                $result = Edit-BATCRelayBotConfig -InstallPath 'C:\does-not-exist' -PassThru
                $result.Success | Should -Be $false
                $result.Errors | Should -Contain "No config.json"
            }
        }

        It "Install-BATCRelayBot returns the reason it stopped" {
            InModuleScope BATCRelayBot {
                Mock Read-Host { '' }
                $result = Stop-Installation -Reason 'Required tools missing' -LogPath $null -PassThru
                $result.Success | Should -Be $false
                $result.Error | Should -Be 'Required tools missing'
            }
        }
    }

    Context "no return path bypasses the switch" {

        # The rule, derived from the code rather than from a list: if a command
        # can return a value, it must offer -PassThru, and every one of those
        # returns must be gated by it. This is what catches the fifth command.
        It "every command that returns a value offers -PassThru" {
            foreach ($command in $Exported) {
                if ((Get-ValueReturn -Command $command).Count -gt 0) {
                    (Get-Command $command).Parameters.Keys |
                        Should -Contain 'PassThru' -Because "$command returns a value"
                }
            }
        }

        It "every returned value passes through the switch" {
            foreach ($command in $Exported) {
                foreach ($return in (Get-ValueReturn -Command $command)) {
                    $return.Pipeline.Extent.Text |
                        Should -Match '\$PassThru' -Because "$command returns unconditionally at line $($return.Extent.StartLineNumber)"
                }
            }
        }

        # -PassThru gates the return statement, and nothing else. A helper
        # called as a bare statement writes its own return value into the
        # command's output just as effectively.
        #
        # Show-PostInstallationMessage did exactly that: it returned a hashtable
        # nothing used and was called without Out-Null, so an install printed
        # two objects. The dump in the test notes shows every key twice, which
        # is what two hashtables look like.
        It "no helper leaks its return value into a command's output" {
            $emits = @{}
            foreach ($file in Get-ChildItem $ModuleRoot -Filter *.ps1 -Recurse) {
                $tree = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
                foreach ($function in $tree.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true)) {
                    $valueReturn = $function.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.ReturnStatementAst] -and
                        $null -ne $node.Pipeline
                    }, $true)
                    if ($valueReturn.Count -gt 0) { $emits[$function.Name] = $true }
                }
            }

            foreach ($command in $Exported) {
                $file = Join-Path $ModuleRoot "Public\$command.ps1"
                $tree = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$null)

                $public = $tree.Find({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq $command
                }, $true)

                foreach ($call in $public.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst]
                }, $true)) {

                    # Only a bare statement reaches the caller's output.
                    #
                    # One level of parent is not enough to tell: "$x = @(Find-
                    # BotProcess ...)" puts a statement block inside the
                    # assignment, so a shallow check called that bare and
                    # reported an assignment as a leak. The whole chain up to
                    # the function has to be statement containers - anything
                    # else on the way consumes the value.
                    $pipeline = $call.Parent
                    if ($pipeline -isnot [System.Management.Automation.Language.PipelineAst]) { continue }

                    # Piped onward: only the last element writes to the output.
                    $elements = $pipeline.PipelineElements
                    if ($elements[$elements.Count - 1] -ne $call) { continue }

                    # ScriptBlockAst belongs here: a function body is one, and
                    # the chain reaches it before the function itself. Leaving
                    # it out made this whole test vacuous - every call broke out
                    # of the walk and nothing was ever checked. It was caught by
                    # putting the leak back into Show-PostInstallationMessage
                    # and watching this test stay green.
                    #
                    # A script block passed as an argument is still caught: its
                    # parent is a ScriptBlockExpressionAst, which is not here.
                    $containers = @(
                        'PipelineAst', 'StatementBlockAst', 'NamedBlockAst', 'ScriptBlockAst',
                        'IfStatementAst', 'SwitchStatementAst', 'TryStatementAst',
                        'CatchClauseAst', 'ForEachStatementAst', 'ForStatementAst',
                        'WhileStatementAst', 'DoWhileStatementAst', 'DoUntilStatementAst'
                    )

                    $node = $pipeline
                    $bare = $true
                    while ($node -and $node -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) {
                        if ($containers -notcontains $node.GetType().Name) { $bare = $false; break }
                        $node = $node.Parent
                    }
                    if (-not $bare) { continue }

                    $name = $call.GetCommandName()
                    if ($name -and $emits.ContainsKey($name)) {
                        throw "$command calls $name as a bare statement at line $($call.Extent.StartLineNumber); its return value would be printed. Assign it or pipe it to Out-Null."
                    }
                }
            }
        }

        It "Start- and Stop-BATCRelayBot need no switch, and have none" {
            foreach ($command in 'Start-BATCRelayBot', 'Stop-BATCRelayBot') {
                (Get-ValueReturn -Command $command).Count | Should -Be 0
                (Get-Command $command).Parameters.Keys | Should -Not -Contain 'PassThru'
            }
        }
    }

    Context "Out-CommandResult itself" {

        It "emits nothing without the switch" {
            InModuleScope BATCRelayBot {
                @(Out-CommandResult -Result @{ Success = $true }).Count | Should -Be 0
            }
        }

        It "emits the object it was given with the switch" {
            InModuleScope BATCRelayBot {
                $given = @{ Success = $true; InstallPath = 'C:\somewhere' }
                $back = Out-CommandResult -Result $given -PassThru
                $back.InstallPath | Should -Be 'C:\somewhere'
            }
        }
    }
}
