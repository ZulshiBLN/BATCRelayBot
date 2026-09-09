# One bot per installation.
#
# On 2026-09-09 two ran at once. Start-BATCRelayBot decided by reading bot.pid
# and asking Get-Process about the number in it; the file was stale, so it
# started a second bot beside a running one. Both answered every chat command,
# the second start truncated the first one's log - which is why the session
# that was actually being used left no trace anywhere - and Stop-BATCRelayBot
# then waited fifteen seconds for a process that was never going to answer and
# terminated it.
#
# The consequence was not a tidy one. A terminated bot loses its ffmpeg
# without closing the capture ffmpeg held on a VoiceMeeter bus, and
# VoiceMeeter's audio engine is then stuck for the whole machine: no browser
# video, no stream, no local file. Restarting the VoiceMeeter process does not
# clear it.
#
# Stop-BATCRelayBot already carried the lesson in a comment - "bot.pid is a
# hint, not the authority" - and this function never got it.

BeforeAll {
    Import-Module "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1" -Force

    function New-BotSandbox {
        $path = Join-Path $env:TEMP ("startbot-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $path -Force | Out-Null

        "print('bot')" | Set-Content (Join-Path $path 'bot.py')
        @{
            python_path              = (Get-Command python -ErrorAction SilentlyContinue).Source
            voicemeeter_path         = ""
            voicemeeter_process_name = ""
            batc_path                = ""
            batc_process_name        = ""
        } | ConvertTo-Json | Set-Content (Join-Path $path 'config.json')

        $path
    }
}

Describe "Start-BATCRelayBot" {

    It "refuses to start a second bot beside a running one" {
        $sandbox = New-BotSandbox
        try {
            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox } {
                param($Path)

                # The authority is the process list, not the pid file.
                Mock Find-BotProcess { @(4242) }
                Mock Start-Process { throw "a second bot was started" }

                $out = ((Start-BATCRelayBot -BotPath $Path 6>&1) | ForEach-Object { "$_" }) -join "`n"

                Should -Invoke Start-Process -Times 0
                $out | Should -Match 'already running'
                $out | Should -Match '4242'
            }
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "does not decide from bot.pid alone" {
        $sandbox = New-BotSandbox
        try {
            # A pid file naming a process that is gone, while a bot really is
            # running. The old check read the file, found nothing alive behind
            # it, and started another one.
            "999999" | Set-Content (Join-Path $sandbox 'bot.pid')

            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox } {
                param($Path)

                Mock Find-BotProcess { @(4242) }
                Mock Start-Process { throw "a second bot was started" }

                Start-BATCRelayBot -BotPath $Path 6>$null

                Should -Invoke Start-Process -Times 0
            }
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "clears a pid file left behind by a bot that is gone" {
        $sandbox = New-BotSandbox
        $pidFile = Join-Path $sandbox 'bot.pid'
        try {
            "999999" | Set-Content $pidFile

            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox } {
                param($Path)

                Mock Find-BotProcess { @() }
                Mock Start-Process { [pscustomobject]@{ Id = 1234 } }

                Start-BATCRelayBot -BotPath $Path 6>$null
            }

            # Rewritten with the new process id rather than left as it was.
            Get-Content $pidFile | Should -Be '1234'
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
