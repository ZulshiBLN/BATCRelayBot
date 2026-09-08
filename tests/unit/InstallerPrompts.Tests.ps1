# I3 and I4, asserted against the installer's own source rather than against a
# number written down beside it.
#
# I3  detection is silent - phases 1 and 2 never prompt
# I4  four prompts on a clean run, six at most
#
# These were guidance until 2026-09-08, and the documentation had drifted from
# the code in both directions: three documents described phases the installer no
# longer had, and the prompt count in the ruleset said "at most four" when six
# is reachable. Counting the source is the only version that cannot drift.

BeforeAll {
    $Root      = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $Installer = Join-Path $Root 'BATCRelayBot\Public\Install-BATCRelayBot.ps1'
    $Private   = Join-Path $Root 'BATCRelayBot\Private'

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

    function Measure-Prompt {
        param([string]$Text)
        ([regex]::Matches($Text, 'Read-Host')).Count
    }

    # A phase calls helpers; their prompts count too.
    function Measure-PhasePrompt {
        param([int]$Phase)
        $body = $Phases[$Phase]
        $total = Measure-Prompt $body
        foreach ($helper in Get-ChildItem $Private -Filter *.ps1) {
            if ($body -match [regex]::Escape($helper.BaseName)) {
                $total += Measure-Prompt ([System.IO.File]::ReadAllText($helper.FullName))
            }
        }
        $total
    }
}

Describe "Installer prompts" {
    It "the installer still has the phases the rules describe" {
        $Phases.Keys | Sort-Object | Should -Be @(0, 1, 2, 3, 4, 5, 6)
    }

    # I3. Detection that stops to ask is detection the user has to sit through,
    # and the whole point of splitting phases 1 and 2 out is that they run.
    It "detection is silent - phases 1 and 2 never prompt" {
        Measure-Prompt $Phases[1] | Should -Be 0
        Measure-Prompt $Phases[2] | Should -Be 0
    }

    It "phases 0, 5 and 6 never prompt either" {
        foreach ($p in 0, 5, 6) { Measure-Prompt $Phases[$p] | Should -Be 0 }
    }

    # I4. Seven or more prompts drops completion from about 90% to about 40%,
    # which is the reason the phases exist at all.
    It "no more than six prompts across the whole run" {
        $total = (Measure-PhasePrompt 3) + (Measure-PhasePrompt 4)
        $total | Should -BeLessOrEqual 6
    }

    It "no more than four in the configuration phase" {
        Measure-PhasePrompt 4 | Should -BeLessOrEqual 4
    }
}
