# The files the installer needs, and whether the published package carries them.
#
# 1.4.0 shipped without bot.py, requirements.txt or config.example.json.
# Publish-Module packages the module folder; those three live one level above
# it. Install-BATCRelayBot stopped with "requirements.txt not found" before
# writing anything, so the release was unusable from the gallery.
#
# It was invisible in testing because every run happened in a checkout, where
# the installer's relative-path fallbacks find the files. Nobody had installed
# the package and run it.
#
# BATCRelayBot.nuspec declared all three and looked like the guarantee against
# exactly this. Publish-Module never reads a nuspec - it was decoration that
# resembled a safeguard.
#
# So this test does not restate the list. It reads what the installer looks for
# and requires the workflow to ship each one.

BeforeAll {
    $Root      = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $Installer = Join-Path $Root 'BATCRelayBot\Private\Start-Installation.ps1'
    $Workflow  = Join-Path $Root '.github\workflows\publish.yml'

    # Every "<name>.<ext> not found in any known location" is the installer
    # saying it cannot proceed without that file.
    $installerText = [System.IO.File]::ReadAllText($Installer)
    $Required = [regex]::Matches($installerText, '"(?<file>[\w.]+\.\w+) not found in any known location"') |
                ForEach-Object { $_.Groups['file'].Value } |
                Sort-Object -Unique
}

Describe "Installer payload" {
    It "the installer names at least one file it cannot proceed without" {
        $Required.Count | Should -BeGreaterThan 0
    }

    It "every file the installer requires exists in the repository" {
        foreach ($file in $Required) {
            Test-Path (Join-Path $Root $file) | Should -Be $true -Because "$file is what the installer looks for"
        }
    }

    # The check that would have caught 1.4.0. If the installer starts needing a
    # fourth file, this fails before a user finds out.
    It "the publish workflow packages every file the installer requires" {
        $workflowText = [System.IO.File]::ReadAllText($Workflow)
        foreach ($file in $Required) {
            $workflowText | Should -Match ([regex]::Escape($file)) -Because "the package is unusable without $file"
        }
    }

    It "the packaging step runs before Publish-Module, not after" {
        $workflowText = [System.IO.File]::ReadAllText($Workflow)

        # The invocation, not a mention of it: the comment explaining why the
        # copy exists names Publish-Module too, and matching that put the
        # ordering check the wrong way round on its first run.
        $call = [regex]::Match($workflowText, '(?m)^\s*Publish-Module\s+-Path')
        $call.Success | Should -Be $true

        $copyAt = $workflowText.IndexOf('Copy-Item -Path $file -Destination $modulePath')
        $copyAt | Should -BeGreaterThan 0
        $copyAt | Should -BeLessThan $call.Index
    }
}
