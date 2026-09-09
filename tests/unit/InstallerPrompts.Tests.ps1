# I3 and I4, asserted against the installer's own source rather than against a
# number written down beside it.
#
# I3  detection is silent - phases 1 and 2 never prompt
# I4  three prompts on a clean run, five at most
#
# These were guidance until 2026-09-08, and the documentation had drifted from
# the code in both directions: three documents described phases the installer no
# longer had, and the prompt count in the ruleset said "at most four" when six
# was reachable. Counting the source is the only version that cannot drift.
#
# The first counter matched helpers by file name against the phase body. Phase 4
# calls Select-AudioDevice, which lives in Get-AudioDevice.ps1, so that file was
# never counted - and the helpers defined inside Install-BATCRelayBot.ps1 itself
# were counted for no phase at all. Phase 3 scored 0 and phase 4 scored 2
# against a bound of 4: the assertion could not fail. Calls are resolved by
# function name now, and followed through the functions they call in turn,
# because Get-DiscordConfiguration prompts only by way of Read-DiscordToken and
# Read-DiscordSnowflake.
#
# What is counted is prompt *sites*, not prompts. Select-AudioDevice has three
# sites - the manual-entry fallback, the selection, and the re-ask - of which a
# clean run reaches one. Sites are therefore an upper bound on prompts, and the
# bound is what protects the number: a new Read-Host anywhere reachable from
# phase 3 or 4 fails this file.

BeforeAll {
    $Root      = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $Module    = Join-Path $Root 'BATCRelayBot'
    $Installer = Join-Path $Module 'Public\Install-BATCRelayBot.ps1'

    $source = [System.IO.File]::ReadAllText($Installer)

    # Split the installer on its phase markers, keeping what belongs to each.
    $markers = [regex]::Matches($source, '(?m)^\s*#\s*-+\s*Phase (?<n>\d+):(?<rest>.*)$')

    # The phases live inside the main function; the helpers are defined after it.
    # Without this bound the last phase runs to the end of the file and absorbs
    # every helper's prompts - it reported three for a phase that has none.
    $bodyEnd = $source.Length
    if ($markers.Count -gt 0) {
        $tail = [regex]::Match($source.Substring($markers[$markers.Count - 1].Index), '(?m)^function\s')
        if ($tail.Success) { $bodyEnd = $markers[$markers.Count - 1].Index + $tail.Index }
    }

    $Phases = @{}
    for ($i = 0; $i -lt $markers.Count; $i++) {
        $start = $markers[$i].Index
        $end   = if ($i + 1 -lt $markers.Count) { $markers[$i + 1].Index } else { $bodyEnd }
        $Phases[[int]$markers[$i].Groups['n'].Value] = $source.Substring($start, $end - $start)
    }

    # Every function in the module: how many times it prompts directly, and
    # which other commands it calls.
    $Prompts = @{}
    $Calls   = @{}

    foreach ($file in Get-ChildItem $Module -Filter *.ps1 -Recurse) {
        $tree = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)

        foreach ($function in $tree.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)) {
            $commands = $function.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true)

            $Prompts[$function.Name] = @($commands | Where-Object { $_.GetCommandName() -eq 'Read-Host' }).Count
            $Calls[$function.Name]   = @($commands | ForEach-Object { $_.GetCommandName() } |
                                         Where-Object { $_ } | Select-Object -Unique)
        }
    }

    # Stop-Installation's Read-Host is "Press Enter to close", on the way out of
    # a run that has already failed. It is a pause, not a question, and it is
    # reachable from every phase - counting it would put a floor of one under
    # phases the rules require to be silent. The test below pins it to that one
    # site, so the exemption cannot quietly grow.
    $NotAQuestion = @('Stop-Installation')

    function Measure-FunctionPrompt {
        param([string]$Name, [string[]]$Seen = @())

        if ($Name -in $NotAQuestion) { return 0 }

        # Cycles are possible and would otherwise recurse until the stack ends.
        if ($Seen -contains $Name -or -not $Prompts.ContainsKey($Name)) { return 0 }
        $Seen = $Seen + $Name

        $total = $Prompts[$Name]
        foreach ($called in $Calls[$Name]) {
            $total += (Measure-FunctionPrompt -Name $called -Seen $Seen)
        }
        return $total
    }

    function Measure-PhasePrompt {
        param([int]$Phase)

        $body = $Phases[$Phase]
        $total = ([regex]::Matches($body, 'Read-Host')).Count

        foreach ($name in $Prompts.Keys) {
            if ($body -match "\b$([regex]::Escape($name))\b") {
                $total += (Measure-FunctionPrompt -Name $name)
            }
        }
        return $total
    }
}

Describe "Installer prompts" {
    It "the installer still has the phases the rules describe" {
        $Phases.Keys | Sort-Object | Should -Be @(0, 1, 2, 3, 4, 5, 6)
    }

    # I3. Detection that stops to ask is detection the user has to sit through,
    # and the whole point of splitting phases 1 and 2 out is that they run.
    It "detection is silent - phases 1 and 2 never prompt" {
        Measure-PhasePrompt 1 | Should -Be 0
        Measure-PhasePrompt 2 | Should -Be 0
    }

    It "phases 0, 5 and 6 never prompt either" {
        foreach ($p in 0, 5, 6) { Measure-PhasePrompt $p | Should -Be 0 }
    }

    # I4. Seven or more prompts drops completion from about 90% to about 40%,
    # which is the reason the phases exist at all.
    #
    # Phase 3 asks whether to install what is missing, and whether to continue
    # without VoiceMeeter. Two sites, at most two prompts.
    It "phase 3 has no more than the two questions it is allowed" {
        Measure-PhasePrompt 3 | Should -BeLessOrEqual 2
    }

    # Phase 4 asks for the token, the server ID and the audio device: three on a
    # clean run. Five sites, because picking a device has a fallback and a
    # re-ask that a clean run does not reach.
    It "phase 4 has no more sites than its three questions need" {
        Measure-PhasePrompt 4 | Should -BeLessOrEqual 5
    }

    It "the whole run stays inside the documented ceiling" {
        (Measure-PhasePrompt 3) + (Measure-PhasePrompt 4) | Should -BeLessOrEqual 7
    }

    It "the one exempt prompt is still just the pause on the way out" {
        $Prompts['Stop-Installation'] | Should -Be 1
        $source | Should -Match 'Press Enter to close'
    }

    # The channel was the fourth question until it stopped configuring
    # anything: the bot joins the channel the caller is in, or one they name.
    It "no longer asks for a voice channel" {
        $Phases[4] | Should -Not -Match 'VoiceChannelId'
        [System.IO.File]::ReadAllText((Join-Path $Module 'Private\Get-DiscordConfiguration.ps1')) |
            Should -Not -Match 'Voice channel ID'
    }
}
