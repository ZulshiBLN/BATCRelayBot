#Requires -Version 5.1

<#
.SYNOPSIS
Fails if anything resembling a real credential enters the repository.

.DESCRIPTION
A security review found a string in the exact shape of a Discord bot token
sitting in two test fixtures, committed on 30 August and reachable from
develop, main and the tags v1.3.10 through v1.3.16 - so it was on GitHub. It
turned out not to be a live token, but nothing in the repository would have
said so either way, and .gitignore cannot help once something is committed.

This test is the standing check. It looks at tracked files rather than the
working directory, because only tracked content can be pushed.

Fixtures should stay obviously fake: a repeated character, or a word like
"placeholder". Anything that looks like it came out of a real credential
generator fails here.
#>

BeforeAll {
    $script:RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path

    # Only tracked files can reach GitHub.
    Push-Location $script:RepoRoot
    try {
        $script:TrackedFiles = @(git ls-files) | Where-Object { $_ }
    } finally {
        Pop-Location
    }

    function Test-LooksSynthetic {
        <#
        Segments built from one repeated character, or carrying an obvious
        placeholder word, are fixtures rather than credentials.
        #>
        param([string]$Value)

        if ($Value -match '(?i)(placeholder|example|dummy|fake|sample|your[_-]?token|xxx+|test[_-]?token)') {
            return $true
        }

        foreach ($segment in $Value.Split('.')) {
            if ($segment.Length -lt 4) { continue }
            $distinct = ($segment.ToCharArray() | Select-Object -Unique).Count
            # "AAAAAAAA" has one distinct character; a real segment has many.
            if ($distinct -le 3) { return $true }
        }
        return $false
    }
}

Describe "No credential-shaped strings in tracked files" {

    It "found tracked files to scan" {
        # Guards against the scan silently passing because it saw nothing.
        $script:TrackedFiles.Count | Should -BeGreaterThan 20
    }

    It "contains nothing shaped like a Discord bot token" {
        # Three base64url segments, the lengths Discord actually issues.
        $pattern = '[A-Za-z0-9_-]{23,28}\.[A-Za-z0-9_-]{6,7}\.[A-Za-z0-9_-]{27,40}'
        $findings = @()

        foreach ($file in $script:TrackedFiles) {
            $path = Join-Path $script:RepoRoot $file
            if (-not (Test-Path $path -PathType Leaf)) { continue }

            $matches = Select-String -Path $path -Pattern $pattern -AllMatches -ErrorAction SilentlyContinue
            foreach ($match in $matches) {
                foreach ($m in $match.Matches) {
                    if (-not (Test-LooksSynthetic -Value $m.Value)) {
                        $findings += "$file line $($match.LineNumber)"
                    }
                }
            }
        }

        $findings | Should -BeNullOrEmpty -Because "a token-shaped string must be an obvious fixture, not a plausible credential"
    }

    It "detects a realistic token, so the check above is not vacuous" {
        # The string that prompted this test. If Test-LooksSynthetic ever
        # starts calling it a fixture, the scan above has stopped working.
        $realistic = 'MzA4OTIzMTY4OTEwNzI2MTc2.COIM8g.LFqo5SoZfTgZ0OmfPy6rx7EXPE8'
        Test-LooksSynthetic -Value $realistic | Should -BeFalse
    }

    It "accepts the repeated-character fixtures the suite uses" {
        Test-LooksSynthetic -Value (("A" * 24) + "." + ("B" * 6) + "." + ("C" * 27)) | Should -BeTrue
    }

    It "contains no config.json, which would carry a live token" {
        $script:TrackedFiles | Should -Not -Contain 'config.json'
    }

    It "still tracks config.example.json, the template users copy" {
        $script:TrackedFiles | Should -Contain 'config.example.json'
    }

    It "contains no .env file" {
        @($script:TrackedFiles | Where-Object { $_ -match '(^|/)\.env($|\.)' }) | Should -BeNullOrEmpty
    }

    It "keeps the example config free of anything resembling a real token" {
        $example = Get-Content (Join-Path $script:RepoRoot 'config.example.json') -Raw
        $example | Should -Match 'YOUR_BOT_TOKEN_HERE'
    }
}
