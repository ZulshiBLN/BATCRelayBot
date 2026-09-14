# On 2026-09-13 the bot died around 22:28 and the log could not say when or
# why. bot_error.log ended at 21:46 on "Audio stream started" - a healthy relay
# writes nothing after that - and the process ended with no traceback, no
# "Stop signal detected" and bot.pid still on disk. TerminateProcess runs no
# Python at all, so nothing inside the process can record an outside kill.
#
# The watcher is the process that can. It starts the bot, holds the handle,
# waits, and appends the exit code to install.log - which survives the restart
# a user makes to recover, unlike bot_error.log, which -RedirectStandardError
# truncates on every start.
#
# Every child here is a stub: a PowerShell script in a TEMP sandbox that sleeps,
# exits with a chosen code, or waits for stop.signal the way bot.py does. No
# test touches the real installation or depends on a bot being up.

BeforeAll {
    Import-Module "$PSScriptRoot\..\..\BATCRelayBot\BATCRelayBot.psm1" -Force

    $script:powershell = (Get-Command powershell.exe).Source

    function New-WatcherSandbox {
        $path = Join-Path $env:TEMP ("watcher-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $path 'logs') -Force | Out-Null
        # The watcher refuses to write into a directory that holds no bot,
        # which is what an uninstalled directory looks like.
        "bot" | Set-Content (Join-Path $path 'bot.py')
        $path
    }

    # A stub child. The body is what the child does; it runs under
    # -ExecutionPolicy Bypass so the machine's policy cannot fail the test.
    function New-Stub {
        param([string]$Sandbox, [string]$Name, [string]$Body)
        $stub = Join-Path $Sandbox "$Name.ps1"
        [System.IO.File]::WriteAllText($stub, $Body, (New-Object System.Text.UTF8Encoding($false)))
        "-NoProfile -ExecutionPolicy Bypass -File `"$stub`""
    }

    function Wait-ForFile {
        param([string]$Path, [string]$Pattern, [int]$Seconds = 10)
        $deadline = (Get-Date).AddSeconds($Seconds)
        while ((Get-Date) -lt $deadline) {
            if ((Test-Path $Path) -and ((Get-Content $Path -Raw -ErrorAction SilentlyContinue) -match $Pattern)) {
                return $true
            }
            Start-Sleep -Milliseconds 200
        }
        return $false
    }

    function Wait-ForPid {
        param([string]$PidFile, [int]$Seconds = 10)
        $deadline = (Get-Date).AddSeconds($Seconds)
        while ((Get-Date) -lt $deadline) {
            $text = Get-Content $PidFile -ErrorAction SilentlyContinue
            if ($text -match '^\d+$') { return [int]$text }
            Start-Sleep -Milliseconds 100
        }
        return $null
    }

    function Remove-Sandbox {
        param([string]$Path)
        foreach ($watcher in @(Find-BotWatcher -BotPath $Path)) {
            Stop-Process -Id $watcher -Force -ErrorAction SilentlyContinue
        }
        $childPid = Get-Content (Join-Path $Path 'bot.pid') -ErrorAction SilentlyContinue
        if ($childPid -match '^\d+$') {
            Stop-Process -Id ([int]$childPid) -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 300
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "The exit line" {

    # Three deaths, three codes. -1 is TerminateProcess - Stop-Process -Force,
    # Task Manager, taskkill /F - and is the one the 2026-09-13 log could not
    # show. Verified by hand on 2026-09-14 before this test existed; the test
    # is so it stays true.
    It "names -1 when the child is terminated from outside" {
        $sandbox = New-WatcherSandbox
        try {
            $arguments = New-Stub -Sandbox $sandbox -Name 'sleep' -Body 'Start-Sleep -Seconds 60'
            Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments | Out-Null

            $childPid = Wait-ForPid -PidFile (Join-Path $sandbox 'bot.pid')
            $childPid | Should -Not -BeNullOrEmpty -Because "the watcher writes the child's pid, not its own"
            (Get-Process -Id $childPid -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty

            Stop-Process -Id $childPid -Force

            $log = Join-Path $sandbox 'install.log'
            Wait-ForFile -Path $log -Pattern 'exit code -1' | Should -Be $true
            Get-Content $log -Raw | Should -Match 'terminated from outside'
            Get-Content $log -Raw | Should -Match "PID $childPid"
        } finally {
            Remove-Sandbox $sandbox
        }
    }

    It "names 0 for a clean exit" {
        $sandbox = New-WatcherSandbox
        try {
            $arguments = New-Stub -Sandbox $sandbox -Name 'clean' -Body 'exit 0'
            Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments | Out-Null

            Wait-ForFile -Path (Join-Path $sandbox 'install.log') -Pattern 'exit code 0\b' | Should -Be $true
        } finally {
            Remove-Sandbox $sandbox
        }
    }

    It "names 1 and points at the traceback for a Python error" {
        $sandbox = New-WatcherSandbox
        try {
            $arguments = New-Stub -Sandbox $sandbox -Name 'fail' -Body 'exit 1'
            Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments | Out-Null

            $log = Join-Path $sandbox 'install.log'
            Wait-ForFile -Path $log -Pattern 'exit code 1\b' | Should -Be $true
            Get-Content $log -Raw | Should -Match 'bot_error\.log'
        } finally {
            Remove-Sandbox $sandbox
        }
    }

    It "writes nothing into a directory the bot has been removed from" {
        # The uninstaller empties the directory. A watcher that wakes after
        # that must not put install.log back, or a clean removal reports a
        # leftover it created itself.
        $sandbox = New-WatcherSandbox
        try {
            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox } {
                param($Path)
                Remove-Item (Join-Path $Path 'bot.py') -Force
                Write-BotExitLine -BotPath $Path -ChildPid 1 -ExitCode -1 -Started (Get-Date)
            }
            Test-Path (Join-Path $sandbox 'install.log') | Should -Be $false
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Restart" {

    # 2026-09-13, 22:28: the bot died with no traceback and bot.pid on disk -
    # almost certainly exit -1 - and stayed dead until somebody noticed. The
    # watcher now brings it back, unless the exit was wanted: exit 0, or
    # stop.signal present at the exit or during the delay. Michel decided on
    # 2026-09-14 that -1 comes back too. Delays are seconds here so the tests
    # do not wait; the default is ten.

    BeforeAll {
        # A stub that fails once and then stays up: exit 1 on the first run,
        # sleep on every later one. The marker file is what tells them apart.
        function New-FailOnceStub {
            param([string]$Sandbox)
            $marker = Join-Path $Sandbox 'ran-once'
            New-Stub -Sandbox $Sandbox -Name 'failonce' -Body "if (Test-Path '$marker') { Start-Sleep -Seconds 60 } else { Set-Content '$marker' 'x'; exit 1 }"
        }
    }

    It "restarts a child that exits 1, and names the attempt" {
        $sandbox = New-WatcherSandbox
        try {
            $arguments = New-FailOnceStub -Sandbox $sandbox
            Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments -RestartDelaySeconds 1 | Out-Null

            $log = Join-Path $sandbox 'install.log'
            Wait-ForFile -Path $log -Pattern 'exit code 1\b' | Should -Be $true
            Wait-ForFile -Path $log -Pattern 'restarted.*attempt 1 of 3' | Should -Be $true

            # bot.pid names the new child, which is up.
            $second = Wait-ForPid -PidFile (Join-Path $sandbox 'bot.pid')
            $second | Should -Not -BeNullOrEmpty
            Start-Sleep -Milliseconds 500
            (Get-Process -Id $second -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty -Because "the restarted child stays up"
            (Get-Content $log -Raw) | Should -Match "\[WARN\].*restarted"
        } finally {
            Remove-Sandbox $sandbox
        }
    }

    It "tells a restarted child that it is one" {
        # Phase 3 reads BATCRELAYBOT_RESTART to rejoin the previous channel;
        # a first start must not carry it, or a start at boot would join.
        $sandbox = New-WatcherSandbox
        try {
            $seen = Join-Path $sandbox 'seen.txt'
            $marker = Join-Path $sandbox 'ran-once'
            $arguments = New-Stub -Sandbox $sandbox -Name 'env' -Body "Add-Content '$seen' ('[' + `$env:BATCRELAYBOT_RESTART + ']'); if (Test-Path '$marker') { exit 0 } else { Set-Content '$marker' 'x'; exit 1 }"
            Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments -RestartDelaySeconds 1 | Out-Null

            Wait-ForFile -Path (Join-Path $sandbox 'install.log') -Pattern 'exit code 0\b' | Should -Be $true
            @(Get-Content $seen) | Should -Be @('[]', '[1]')
        } finally {
            Remove-Sandbox $sandbox
        }
    }

    It "does not restart after a clean exit" {
        $sandbox = New-WatcherSandbox
        try {
            $arguments = New-Stub -Sandbox $sandbox -Name 'clean' -Body 'exit 0'
            $watcher = Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments -RestartDelaySeconds 1
            $log = Join-Path $sandbox 'install.log'
            Wait-ForFile -Path $log -Pattern 'exit code 0\b' | Should -Be $true

            Start-Sleep -Seconds 2
            (Get-Content $log -Raw) | Should -Not -Match 'restarted'
            (Get-Process -Id $watcher.Id -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty -Because "a watcher with nothing to watch ends"
        } finally {
            Remove-Sandbox $sandbox
        }
    }

    It "does not restart a child that was stopped on purpose, and clears the signal" {
        # Stop-BATCRelayBot's forced path: signal written, bot did not
        # answer, killed. -1 with the signal present is wanted.
        $sandbox = New-WatcherSandbox
        try {
            $arguments = New-Stub -Sandbox $sandbox -Name 'sleep' -Body 'Start-Sleep -Seconds 60'
            $watcher = Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments -RestartDelaySeconds 1
            $childPid = Wait-ForPid -PidFile (Join-Path $sandbox 'bot.pid')

            $signal = Join-Path $sandbox 'stop.signal'
            New-Item $signal -ItemType File | Out-Null
            Stop-Process -Id $childPid -Force

            $log = Join-Path $sandbox 'install.log'
            Wait-ForFile -Path $log -Pattern 'exit code -1' | Should -Be $true
            Start-Sleep -Seconds 2
            (Get-Content $log -Raw) | Should -Not -Match 'restarted'
            Test-Path $signal | Should -Be $false -Because "a leftover signal would stop the next bot within a second"
            (Get-Process -Id $watcher.Id -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        } finally {
            Remove-Sandbox $sandbox
        }
    }

    It "does not restart when the signal arrives during the delay" {
        # Stop-BATCRelayBot finding no bot but a live watcher writes the
        # signal; the watcher has to be looking for it while it waits.
        $sandbox = New-WatcherSandbox
        try {
            $arguments = New-Stub -Sandbox $sandbox -Name 'fail' -Body 'exit 1'
            $watcher = Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments -RestartDelaySeconds 4
            $log = Join-Path $sandbox 'install.log'
            Wait-ForFile -Path $log -Pattern 'exit code 1\b' | Should -Be $true

            $signal = Join-Path $sandbox 'stop.signal'
            New-Item $signal -ItemType File | Out-Null

            $deadline = (Get-Date).AddSeconds(8)
            while ((Get-Process -Id $watcher.Id -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
            (Get-Process -Id $watcher.Id -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty -Because "the signal ends the wait"
            (Get-Content $log -Raw) | Should -Not -Match 'restarted'
            (Get-Content $log -Raw) | Should -Match 'stop.signal'
            Test-Path $signal | Should -Be $false
        } finally {
            Remove-Sandbox $sandbox
        }
    }

    It "gives up after three restarts in an hour, and says so" {
        $sandbox = New-WatcherSandbox
        try {
            $arguments = New-Stub -Sandbox $sandbox -Name 'fail' -Body 'exit 1'
            $watcher = Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments -RestartDelaySeconds 1
            $log = Join-Path $sandbox 'install.log'

            Wait-ForFile -Path $log -Pattern '\[ERROR\].*(giving up|not restarting)' -Seconds 30 | Should -Be $true
            $lines = Get-Content $log
            @($lines | Where-Object { $_ -match 'restarted' }).Count | Should -Be 3
            @($lines | Where-Object { $_ -match 'exit code 1\b' }).Count | Should -Be 4

            Start-Sleep -Milliseconds 500
            (Get-Process -Id $watcher.Id -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
        } finally {
            Remove-Sandbox $sandbox
        }
    }
}

Describe "Start, Stop and Status around a restarting watcher" {

    BeforeAll {
        function New-BotSandbox {
            $path = New-WatcherSandbox
            @{
                python_path              = $script:powershell
                voicemeeter_path         = ""
                voicemeeter_process_name = ""
                batc_path                = ""
                batc_process_name        = ""
            } | ConvertTo-Json | Set-Content (Join-Path $path 'config.json')
            $path
        }
    }

    It "Start-BATCRelayBot refuses while a watcher is about to start a bot" {
        $sandbox = New-BotSandbox
        try {
            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox } {
                param($Path)
                Mock Find-BotProcess { @() }
                Mock Find-BotWatcher { @(77) }
                Mock Start-BotWatcher { throw "a second watcher was started" }

                $out = ((Start-BATCRelayBot -BotPath $Path 6>&1) | ForEach-Object { "$_" }) -join "`n"

                Should -Invoke Start-BotWatcher -Times 0
                $out | Should -Match 'watcher'
                $out | Should -Match '77'
                $out | Should -Match 'Stop-BATCRelayBot'
            }
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Start-BATCRelayBot clears a stale stop.signal before the bot can read it" {
        $sandbox = New-BotSandbox
        $signal = Join-Path $sandbox 'stop.signal'
        New-Item $signal -ItemType File | Out-Null
        try {
            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox } {
                param($Path)
                Mock Find-BotProcess { @() }
                Mock Find-BotWatcher { @() }
                Mock Start-BotWatcher {
                    Test-Path (Join-Path $Path 'stop.signal') | Should -Be $false -Because "the bot checks for it every second"
                    "1234" | Set-Content (Join-Path $Path 'bot.pid')
                    [pscustomobject]@{ Id = 77 }
                }
                Mock Test-BotPidAlive { $true }

                Start-BATCRelayBot -BotPath $Path 6>$null
                Should -Invoke Start-BotWatcher -Times 1
            }
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Stop-BATCRelayBot ends a watcher that is between two bots" {
        # Find-BotProcess sees no child during the delay; before this, Stop
        # said "No running bot found" and the watcher restarted the bot
        # anyway.
        $sandbox = New-WatcherSandbox
        try {
            $arguments = New-Stub -Sandbox $sandbox -Name 'fail' -Body 'exit 1'
            $watcher = Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments -RestartDelaySeconds 6
            Wait-ForFile -Path (Join-Path $sandbox 'install.log') -Pattern 'exit code 1\b' | Should -Be $true

            $out = ((Stop-BATCRelayBot -BotPath $sandbox 6>&1) | ForEach-Object { "$_" }) -join "`n"

            $out | Should -Match 'restart'
            (Get-Process -Id $watcher.Id -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
            Test-Path (Join-Path $sandbox 'stop.signal') | Should -Be $false
            (Get-Content (Join-Path $sandbox 'install.log') -Raw) | Should -Not -Match 'restarted'
        } finally {
            Remove-Sandbox $sandbox
        }
    }

    It "Get-BATCRelayBotStatus says restarting, not 'not running'" {
        $sandbox = New-WatcherSandbox
        try {
            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox } {
                param($Path)
                Mock Find-BotProcess { @() }
                Mock Find-BotWatcher { @(77) }

                $out = ((Get-BATCRelayBotStatus -BotPath $Path 6>&1) | ForEach-Object { "$_" }) -join "`n"
                $status = Get-BATCRelayBotStatus -BotPath $Path -PassThru 6>$null

                $out | Should -Match 'RESTARTING'
                $out | Should -Not -Match 'NOT RUNNING'
                $status.IsRunning | Should -Be $false
                $status.IsRestarting | Should -Be $true
                $status.WatcherId | Should -Be 77
            }
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Stop-BotProcess leaves the signal for the watcher when it has to terminate" {
        $sandbox = New-WatcherSandbox
        try {
            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox } {
                param($Path)
                Mock Find-BotProcess { @(4242) }
                Mock Find-BotWatcher { @(77) }
                Mock Stop-Process { }

                $result = Stop-BotProcess -BotPath $Path -TimeoutSeconds 1

                $result.Method | Should -Be 'forced'
                Test-Path (Join-Path $Path 'stop.signal') | Should -Be $true -Because "-1 with the signal present is how the watcher knows the kill was wanted"
            }
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Stop-BotProcess removes the signal when no watcher will" {
        # A bot started by hand has no watcher; a leftover signal would stop
        # the next one within a second.
        $sandbox = New-WatcherSandbox
        try {
            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox } {
                param($Path)
                Mock Find-BotProcess { @(4242) }
                Mock Find-BotWatcher { @() }
                Mock Stop-Process { }

                Stop-BotProcess -BotPath $Path -TimeoutSeconds 1 | Out-Null

                Test-Path (Join-Path $Path 'stop.signal') | Should -Be $false
            }
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Stop-BotProcess ends the watcher first when it cannot write the signal" {
        # Without a signal, -1 looks unwanted and the watcher would bring the
        # bot back. A directory that refuses the file is the only such case.
        $sandbox = New-WatcherSandbox
        try {
            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox } {
                param($Path)
                Mock Find-BotProcess { @(4242) }
                Mock New-Item { throw "cannot write here" } -ParameterFilter { $ItemType -eq 'File' }
                Mock Stop-BotWatcher { @(77) }
                Mock Stop-Process { }

                $result = Stop-BotProcess -BotPath $Path -TimeoutSeconds 1

                $result.Method | Should -Be 'forced'
                Should -Invoke Stop-BotWatcher -Times 1
            }
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "The exit-code table" {

    # Get-ExitCodeMeaning is the authority; docs/TROUBLESHOOTING.md mirrors it
    # for someone with a dead bot and no PowerShell open. The codes are read
    # out of the switch, not retyped here.
    It "in docs/TROUBLESHOOTING.md names every code the watcher can explain" {
        $source = Join-Path $PSScriptRoot '..\..\BATCRelayBot\Private\Watch-BotProcess.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$null, [ref]$null)
        $function = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ExitCodeMeaning' }, $true)
        $switch = $function.Find({ param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst] }, $true)
        $codes = @($switch.Clauses | ForEach-Object { $_.Item1.Extent.Text })
        $codes.Count | Should -BeGreaterThan 3 -Because "the switch is where the codes live"

        $doc = Get-Content (Join-Path $PSScriptRoot '..\..\docs\TROUBLESHOOTING.md') -Raw
        foreach ($code in $codes) {
            $doc | Should -Match ('\| `' + [regex]::Escape($code) + '` \|') -Because "exit code $code has a meaning the table does not give"
        }
    }
}

Describe "What the child is told" {

    # bot.py's session header names the module version, and the watcher is
    # the only process that knows it. Read from the module, not retyped.
    It "hands the module version to the bot through the environment" {
        $sandbox = New-WatcherSandbox
        try {
            $seen = Join-Path $sandbox 'seen.txt'
            $arguments = New-Stub -Sandbox $sandbox -Name 'env' -Body "Set-Content -Path '$seen' -Value `$env:BATCRELAYBOT_MODULE_VERSION; exit 0"
            Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments | Out-Null
            Wait-ForFile -Path (Join-Path $sandbox 'install.log') -Pattern 'exit code 0\b' | Should -Be $true

            $expected = InModuleScope BATCRelayBot { Get-ModuleVersion }
            $expected | Should -Not -BeNullOrEmpty
            "$(Get-Content $seen -Raw)".Trim() | Should -Be $expected
        } finally {
            Remove-Sandbox $sandbox
        }
    }
}

Describe "Rotation" {

    # Rotate before start, or the redirect has already truncated the file
    # being rotated. Checked by content rather than by count: both files exist
    # either way, and only the previous session's last line proves the order.
    It "keeps the previous session's last line in the rotated file" {
        $sandbox = New-WatcherSandbox
        $current = Join-Path $sandbox 'logs\bot_error.log'
        try {
            $arguments = New-Stub -Sandbox $sandbox -Name 'first' -Body '[Console]::Error.WriteLine("first session last line"); exit 0'
            Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments | Out-Null
            Wait-ForFile -Path (Join-Path $sandbox 'install.log') -Pattern 'exit code 0\b' | Should -Be $true

            $arguments = New-Stub -Sandbox $sandbox -Name 'second' -Body '[Console]::Error.WriteLine("second"); exit 0'
            Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments | Out-Null
            Wait-ForFile -Path $current -Pattern 'second' | Should -Be $true

            $rotated = @(Get-ChildItem (Join-Path $sandbox 'logs') -Filter 'bot_error.*.log')
            $rotated.Count | Should -Be 1
            Get-Content $rotated[0].FullName -Raw | Should -Match 'first session last line'
            Get-Content $current -Raw | Should -Not -Match 'first session'
        } finally {
            Remove-Sandbox $sandbox
        }
    }

    It "keeps five session logs in total, the current one included" {
        $sandbox = New-WatcherSandbox
        $logs = Join-Path $sandbox 'logs'
        try {
            InModuleScope BATCRelayBot -Parameters @{ Logs = $logs } {
                param($Logs)
                for ($session = 1; $session -le 7; $session++) {
                    Invoke-BotLogRotation -LogsDirectory $Logs -Keep 5
                    "session $session" | Set-Content (Join-Path $Logs 'bot_error.log')
                    # Timestamped names collide within one second.
                    Start-Sleep -Milliseconds 1100
                }
            }

            $all = @(Get-ChildItem $logs -Filter 'bot_error*.log')
            $all.Count | Should -Be 5
            Get-Content (Join-Path $logs 'bot_error.log') | Should -Be 'session 7'

            # The oldest went first.
            $kept = $all | Where-Object { $_.Name -ne 'bot_error.log' } | ForEach-Object { Get-Content $_.FullName }
            $kept | Should -Not -Contain 'session 1'
            $kept | Should -Not -Contain 'session 2'
            $kept | Should -Contain 'session 3'
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Finding the watcher" {

    It "is found by the directory it watches, and ended by Stop-BotWatcher" {
        $sandbox = New-WatcherSandbox
        try {
            $arguments = New-Stub -Sandbox $sandbox -Name 'sleep' -Body 'Start-Sleep -Seconds 60'
            $watcher = Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments
            Wait-ForPid -PidFile (Join-Path $sandbox 'bot.pid') | Should -Not -BeNullOrEmpty

            $found = @(Find-BotWatcher -BotPath $sandbox)
            $found | Should -Contain $watcher.Id

            # Another directory's watcher is not this one's.
            $other = Join-Path $env:TEMP ("watcher-other-" + [guid]::NewGuid().ToString('N'))
            @(Find-BotWatcher -BotPath $other).Count | Should -Be 0

            Stop-BotWatcher -BotPath $sandbox
            Start-Sleep -Milliseconds 300
            @(Find-BotWatcher -BotPath $sandbox).Count | Should -Be 0

            # Ending the watcher does not end the bot - that is Stop-BotProcess's job.
            $childPid = [int](Get-Content (Join-Path $sandbox 'bot.pid'))
            (Get-Process -Id $childPid -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        } finally {
            Remove-Sandbox $sandbox
        }
    }
}

Describe "Start-BATCRelayBot with a watcher" {

    BeforeAll {
        function New-BotSandbox {
            $path = New-WatcherSandbox
            @{
                python_path              = $script:powershell
                voicemeeter_path         = ""
                voicemeeter_process_name = ""
                batc_path                = ""
                batc_process_name        = ""
            } | ConvertTo-Json | Set-Content (Join-Path $path 'config.json')
            $path
        }
    }

    It "reports the bot's pid from the watcher, not the watcher's own" {
        $sandbox = New-BotSandbox
        try {
            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox } {
                param($Path)
                Mock Find-BotProcess { @() }
                # The watcher, standing in: it writes the child's pid and
                # returns its own process.
                Mock Start-BotWatcher {
                    "4321" | Set-Content (Join-Path $Path 'bot.pid')
                    [pscustomobject]@{ Id = 77 }
                }
                Mock Test-BotPidAlive { $true }

                $out = ((Start-BATCRelayBot -BotPath $Path 6>&1) | ForEach-Object { "$_" }) -join "`n"

                $out | Should -Match 'PID 4321'
                $out | Should -Match 'watch(ed|er).*77'
            }
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "says so when the watcher never reports a pid, instead of hiding it" {
        $sandbox = New-BotSandbox
        try {
            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox } {
                param($Path)
                Mock Find-BotProcess { @() }
                Mock Start-BotWatcher { [pscustomobject]@{ Id = 77 } }

                $out = ((Start-BATCRelayBot -BotPath $Path -PidTimeoutSeconds 1 6>&1) | ForEach-Object { "$_" }) -join "`n"

                $out | Should -Match 'did not report'
                $out | Should -Match 'install\.log'
            }
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "Stop-BATCRelayBot" {

    It "records a forced termination in install.log" {
        $sandbox = New-WatcherSandbox
        try {
            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox } {
                param($Path)
                Mock Find-BotProcess { @(4242) }
                Mock Stop-BotProcess { @{ Stopped = $true; Method = 'forced'; ProcessIds = @(4242) } }

                Stop-BATCRelayBot -BotPath $Path 6>$null
            }

            $log = Get-Content (Join-Path $sandbox 'install.log') -Raw
            $log | Should -Match 'terminated'
            $log | Should -Match '4242'
            $log | Should -Match '\[WARN\]'
        } finally {
            Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "leaves the watcher alive to record the exit" {
        $sandbox = New-WatcherSandbox
        try {
            $arguments = New-Stub -Sandbox $sandbox -Name 'sleep' -Body 'Start-Sleep -Seconds 60'
            $watcher = Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments
            Wait-ForPid -PidFile (Join-Path $sandbox 'bot.pid') | Should -Not -BeNullOrEmpty

            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox } {
                param($Path)
                Mock Find-BotProcess { @(4242) }
                Mock Stop-BotProcess { @{ Stopped = $true; Method = 'graceful'; ProcessIds = @(4242) } }
                Stop-BATCRelayBot -BotPath $Path 6>$null
            }

            (Get-Process -Id $watcher.Id -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        } finally {
            Remove-Sandbox $sandbox
        }
    }
}

Describe "The uninstaller and the watcher" {

    # The uninstaller kills the child, which wakes the watcher to append into
    # the directory being cleared - and Write-InstallLog recreates the file.
    # So the watcher goes first. Proven by order, not by racing: the stop is
    # mocked to record whether a watcher was still alive when it ran.
    It "ends the watcher before it stops the bot" {
        $sandbox = New-WatcherSandbox
        "config" | Set-Content (Join-Path $sandbox 'config.json')
        try {
            $arguments = New-Stub -Sandbox $sandbox -Name 'sleep' -Body 'Start-Sleep -Seconds 60'
            Start-BotWatcher -BotPath $sandbox -Executable $script:powershell -Arguments $arguments | Out-Null
            $childPid = Wait-ForPid -PidFile (Join-Path $sandbox 'bot.pid')
            $childPid | Should -Not -BeNullOrEmpty

            InModuleScope BATCRelayBot -Parameters @{ Path = $sandbox; Child = $childPid } {
                param($Path, $Child)

                $script:watchersAtStop = -1
                Mock Stop-BotProcess {
                    $script:watchersAtStop = @(Find-BotWatcher -BotPath $BotPath).Count
                    Stop-Process -Id $Child -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                    @{ Stopped = $true; Method = 'forced'; ProcessIds = @($Child) }
                }

                $result = Invoke-SecureUninstall -BotPath $Path -DependencyChoices @{} -LogDirectory $Path 6>$null

                $script:watchersAtStop | Should -Be 0 -Because "a live watcher would write install.log into the emptied directory"
                $result.Leftovers | Should -Not -Contain (Join-Path $Path 'install.log')
                @(Get-ChildItem $Path -Recurse -File).Name | Should -Be @('uninstall.log')
                Get-Content (Join-Path $Path 'uninstall.log') -Raw | Should -Match 'watcher'
            }
        } finally {
            Remove-Sandbox $sandbox
        }
    }
}
